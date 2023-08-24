import 'package:fuse_wallet_sdk/fuse_wallet_sdk.dart';

import 'migrate_funds_action.dart';

void main(List<String> arguments) async {
  final publicKey = "add a public key";

  // Megatron and Shakespeare are just names
  // to make it easier to identify wallets.

  final walletMegatronPrivateKey =
      "Add a private key here";
  final megatronWalletAddress = "Add a wallet address";

  final shakespearePrivateKey =
      "Add a private key here";
  final shakespeareWalletAddress = "Add a wallet address";

  final megatronCredentials = EthPrivateKey.fromHex(walletMegatronPrivateKey);
  final shakespeareCredentials = EthPrivateKey.fromHex(shakespearePrivateKey);

  final fuseWalletSDK = FuseWalletSDK(publicKey);
  final exceptionOrJWT = await fuseWalletSDK.authenticate(megatronCredentials);

  if (exceptionOrJWT.hasError) {
    print("An error occurred while authenticating.");
    return;
  }

  final exceptionOrWallet = await fuseWalletSDK.fetchWallet();

  if (exceptionOrWallet.hasError) {
    print("An error occurred while getting wallet.");
    return;
  }

  final migrateFundsAction = MigrateFundsAction(
    fuseWalletSDK: fuseWalletSDK,
    from: shakespeareWalletAddress,
    to: megatronWalletAddress,
    credentials: shakespeareCredentials,
  );

  migrateFundsAction.execute();
}

void _onSmartWalletEvent(SmartWalletEvent event) {
  switch (event.name) {
    case "smartWalletCreationStarted":
      print('smartWalletCreationStarted ${event.data.toString()}');
      break;
    case "transactionHash":
      print('transactionHash ${event.data.toString()}');
      break;
    case "smartWalletCreationSucceeded":
      print('smartWalletCreationSucceeded ${event.data.toString()}');
      break;
    case "smartWalletCreationFailed":
      print('smartWalletCreationFailed ${event.data.toString()}');
      break;
  }
}
