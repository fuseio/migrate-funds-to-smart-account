import 'package:fuse_wallet_sdk/fuse_wallet_sdk.dart';

import 'format.dart';
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

  Future<void> execute() async {
    await _transferERC20Tokens();
    await _transferFuseToken();
    await _transferCollectibles();
  }

  Future<void> _transferCollectibles() async {
    final collectibles = await _getCollectibles();

    if (collectibles.isEmpty) {
      print("Wallet does not have any collectibles.");
      return;
    }

    for (final collectible in collectibles) {
      await _transferCollectible(collectible);
    }
  }

  Future<dynamic> _transferCollectible(Collectible collectible) async {
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
      return;
    }

    final smartWalletEventStream = exceptionOrStream.data!;
    final txHash = await _waitTransactionSucceeded(smartWalletEventStream);

    print(
      "Transferred ${collectible.name} successfully. "
      "Transaction hash: $txHash",
    );

    return txHash;
  }

  Future<String> _waitTransactionSucceeded(
    Stream<SmartWalletEvent> smartWalletEventStream,
  ) async {
    final transactionHashEvent =
        await smartWalletEventStream.firstWhere(_onTransactionSucceeded);

    return transactionHashEvent.data["txHash"];
  }

  Future<List<Collectible>> _getCollectibles() async {
    print("Getting collectibles...");

    final nftModule = fuseWalletSDK.nftModule;

    final exceptionOrCollectibles =
        await nftModule.getCollectiblesByOwner(from);

    if (exceptionOrCollectibles.hasError) {
      print("An error occurred while getting collectibles.");
      return [];
    }

    final account = exceptionOrCollectibles.data!;
    final collectibles = account.collectibles;

    collectibles.removeWhere((collectible) {
      return collectible.collection.name.contains('Bound');
    });

    return collectibles;
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

    final fuseBalance = exceptionOrFuseBalance.data!;

    if (fuseBalance > BigInt.zero) {
      final fuseToken = Token(
        address: Variables.NATIVE_TOKEN_ADDRESS,
        name: "FUSE",
        symbol: "FUSE",
        amount: fuseBalance,
        decimals: 18,
      );

      await _transferTokenToNewWallet(fuseToken);
    } else {
      print("There aren't any FUSE in the wallet.");
      return;
    }
  }

  Future<String> _transferTokenToNewWallet(Token token) async {
    print("Transferring ${token.name}...");

    final tokenBalance = Formatter.fromWei(token.amount, token.decimals);

    final exceptionOrStream = await _transferToken(
      tokenAddress: token.address,
      tokenBalance: tokenBalance.toString(),
    );

    if (exceptionOrStream.hasError) {
      print("An error occurred while transferring ${token.name}");
      return '';
    }

    final smartWalletEventStream = exceptionOrStream.data!;
    final txHash = await _waitTransactionSucceeded(smartWalletEventStream);

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

    return tokens.toList();
  }

  Future<List<TokenDetails>> _getTokensInWallet() async {
    final exceptionOrTokenList =
        await fuseWalletSDK.explorerModule.getTokenList(from);

    if (exceptionOrTokenList.hasError) {
      final error = exceptionOrTokenList.error.toString();
      if (error == "Exception: No tokens found") return [];

      print("An error occurred while getting tokens in wallet.");
      return [];
    }

    final tokenList = exceptionOrTokenList.data!;
    return tokenList.result;
  }

  bool _onTransactionSucceeded(element) {
    return element.name == "transactionSucceeded";
  }

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
