import 'package:dio/dio.dart';
import 'package:fuse_wallet_sdk/fuse_wallet_sdk.dart';
import 'package:collection/collection.dart';

import 'token.dart';

class MigrateFundsAction {
  final FuseWalletSDK fuseWalletSDK;
  final String from;
  final String to;
  final EthPrivateKey credentials;

  const MigrateFundsAction({
    required this.fuseWalletSDK,
    required this.from,
    required this.to,
    required this.credentials,
  });

  void execute() async {
    await _transferERC20Tokens();
    await _transferFuseToken();
    await _transferCollectibles();
  }

  static const sbtAddress = "0x1dFb7497c29570eD7A7a162782C47f63B5829c49";

  Future<void> _transferCollectibles() async {
    final collectibles = await _getCollectibles();

    if (collectibles.isEmpty) {
      print("User does not have any collectibles.");
      return;
    }

    for (final collectible in collectibles) {
      // Do not attempt to transfer SBT since it cannot be transferred.
      final collectibleAddress = collectible.collection.address.toLowerCase();
      if (collectibleAddress == sbtAddress.toLowerCase()) continue;

      await _transferCollectible(collectible);
    }

    await _migrateSBTByMintingANewOne(collectibles: collectibles);
  }

  Future<String> _transferCollectible(Collectible collectible) async {
    final tokenID = num.parse(collectible.tokenId);

    final exceptionOrStream = await fuseWalletSDK.transferNft(
      credentials,
      collectible.collection.address,
      to,
      tokenID,
    );

    if (exceptionOrStream.hasError) {
      final message = "An error occurred while transferring "
          "the collectible: ${collectible.name}";

      print(message);
      throw Exception(message);
    }

    final smartWalletEventStream = exceptionOrStream.data!;
    final txHash = await _waitForTxHash(smartWalletEventStream);

    print(
      "Transferred ${collectible.name} successfully. "
      "Transaction hash: $txHash",
    );

    return txHash;
  }

  Future<String> _waitForTxHash(
    Stream<SmartWalletEvent> smartWalletEventStream,
  ) async {
    final transactionHashEvent =
        await smartWalletEventStream.firstWhere(_onTransactionHash);

    return transactionHashEvent.data["txHash"];
  }

  Future<void> _migrateSBTByMintingANewOne({
    required List<Collectible> collectibles,
  }) async {
    final sbt = await _findSBT(collectibles);

    if (sbt == null) {
      print("User does not have an SBT.");
      return;
    }

    await _mintSBT(sbt);
  }

  Future<void> _mintSBT(Collectible? sbt) async {
    final response = await _makeRequestToMintSBT(sbt);

    if (response.statusCode == 200) {
      print("Started minting SBT successfully.");
    } else {
      print("Failed to start minting SBT. Error: ${response.data}");
    }
  }

  Future<Response<dynamic>> _makeRequestToMintSBT(Collectible? sbt) async {
    final url =
        "https://api-staging.voltage.finance/api/notifications/mint-sbt";

    final jwt = "Put your JWT here";

    final requestBody = {
      "walletAddress": to,
      "phoneNumber": "+905433723255",
      "descriptorUri": sbt!.descriptorUri,
    };

    return Dio().post(
      url,
      data: requestBody,
      options: Options(
        headers: {'Authorization': 'Bearer $jwt'},
        validateStatus: (_) => true,
      ),
    );
  }

  Future<Collectible?> _findSBT(List<Collectible> collectibles) async {
    final sbt = collectibles.firstWhereOrNull(
      (element) {
        final collectionAddress = element.collection.address.toLowerCase();
        return collectionAddress == sbtAddress.toLowerCase();
      },
    );

    return sbt;
  }

  Future<List<Collectible>> _getCollectibles() async {
    print("Getting collectibles...");

    final nftSection = fuseWalletSDK.nftModule;

    // TODO: Change the wallet address below.
    final exceptionOrCollectibles =
        await nftSection.getCollectiblesByOwner(from);

    if (exceptionOrCollectibles.hasError) {
      print("An error occurred while getting collectibles.");
      throw exceptionOrCollectibles.error!;
    }

    final account = exceptionOrCollectibles.data!;
    return account.collectibles;
  }

  Future<void> _transferERC20Tokens() async {
    final tokensThatHaveBalance = await _getTokensThatHaveBalance();

    for (final token in tokensThatHaveBalance) {
      await _transferTokenToNewWallet(token);
    }
  }

  Future<void> _transferFuseToken() async {
    final exceptionOrFuseBalance =
        await fuseWalletSDK.explorerModule.getNativeBalance(from);

    if (exceptionOrFuseBalance.hasError) {
      print("An error occurred while getting FUSE balance.");
      return;
    }

    final fuseBalance = exceptionOrFuseBalance.data;

    if (fuseBalance != null && fuseBalance != BigInt.zero) {
      print("FUSE balance: $fuseBalance");
    } else {
      print("There aren't any FUSE in the wallet.");
      return;
    }

    final fuseToken = Token(
      address: Variables.NATIVE_TOKEN_ADDRESS,
      name: "FUSE",
      symbol: "FUSE",
      amount: fuseBalance,
      decimals: 18,
    );

    await _transferTokenToNewWallet(fuseToken);
  }

  Future<String> _transferTokenToNewWallet(Token token) async {
    print("Transferring ${token.name}...");

    final tokenBalance = token.getBalance(true);

    final exceptionOrStream = await _transferToken(
      tokenAddress: token.address,
      tokenBalance: tokenBalance,
    );

    if (exceptionOrStream.hasError) {
      print("An error occurred while transferring ${token.name}");
      throw Exception("Failed to transfer token: ${token.name}");
    }

    final smartWalletEventStream = exceptionOrStream.data!;
    final txHash = await _waitForTxHash(smartWalletEventStream);

    print(
      "Transferred $tokenBalance ${token.symbol} successfully. "
      "Transaction hash: $txHash",
    );

    return txHash;
  }

  Future<DC<Exception, Stream<SmartWalletEvent>>> _transferToken({
    required String tokenAddress,
    required String tokenBalance,
  }) async {
    return fuseWalletSDK.transferToken(
      credentials,
      tokenAddress,
      to,
      tokenBalance,
    );
  }

  Future<List<Token>> _getTokensThatHaveBalance() async {
    final tokenDetailsList = await _getTokensInWallet();
    final erc20Tokens = tokenDetailsList.whereType<ERC20>().toList();
    final tokens = erc20Tokens.map(_toToken).toList();

    return tokens.where(_balanceIsNotZero).toList();
  }

  Future<List<TokenDetails>> _getTokensInWallet() async {
    final exceptionOrTokenList =
        await fuseWalletSDK.explorerModule.getTokenList(from);

    if (exceptionOrTokenList.hasError) {
      final error = exceptionOrTokenList.error.toString();
      if (error == "Exception: No tokens found") return [];

      print("An error occurred while getting tokens in wallet.");
      throw Exception("Failed to get tokens in wallet.");
    }

    final tokenList = exceptionOrTokenList.data!;
    return tokenList.result;
  }

  bool _onTransactionHash(element) => element.name == "transactionHash";

  bool _balanceIsNotZero(Token element) => element.getBalance() != "0";

  Token _toToken(ERC20 erc20Token) {
    return Token(
      address: erc20Token.address,
      name: erc20Token.name,
      symbol: erc20Token.symbol,
      amount: erc20Token.amount,
      decimals: erc20Token.decimals,
    );
  }
}
