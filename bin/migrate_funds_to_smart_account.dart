import 'dart:io';

import 'package:args/args.dart';
import 'package:fuse_wallet_sdk/fuse_wallet_sdk.dart';

import 'migrate_funds_action.dart';

void main(List<String> arguments) async {
  final argResults = _parseArgs(arguments);
  final privateKey = argResults["privateKey"] as String;
  String? toWalletAddress = argResults["toWalletAddress"];

  // TODO: Add your public key.
  final publicKey = "";

  if (publicKey.isEmpty) {
    print("Public key is not provided.");
    exit(0);
  }

  final credentials = EthPrivateKey.fromHex(privateKey);

  toWalletAddress ??= await _getAccountAbstractionWalletAddress(
    publicKey,
    credentials,
    toWalletAddress,
  );

  final oldFuseWalletSDK = FuseWalletSDK(publicKey);
  final fromWalletAddress =
      await _getFromWalletAddress(oldFuseWalletSDK, credentials);

  final migrateFundsAction = MigrateFundsAction(
    fuseWalletSDK: oldFuseWalletSDK,
    from: fromWalletAddress,
    to: toWalletAddress,
    credentials: credentials,
  );

  try {
    await migrateFundsAction.execute();
    print("New wallet address: $toWalletAddress");
    exit(1);
  } catch (exception) {
    print("An error occurred: ${exception.toString()}");
    exit(0);
  }
}

ArgResults _parseArgs(List<String> arguments) {
  final parser = ArgParser();
  parser.addOption("privateKey", mandatory: true);
  parser.addOption("toWalletAddress");
  return parser.parse(arguments);
}

Future<String> _getAccountAbstractionWalletAddress(
  String publicKey,
  EthPrivateKey credentials,
  String? toWalletAddress,
) async {
  print(
    "The toWalletAddress is not provided in the args. "
    "Getting it by initializing the new AA SDK.",
  );

  final fuseSDK = await FuseSDK.init(publicKey, credentials);

  // The new Account Abstraction wallet address.
  toWalletAddress = fuseSDK.wallet.getSender();

  return toWalletAddress;
}

Future<String> _getFromWalletAddress(
  FuseWalletSDK oldFuseWalletSDK,
  EthPrivateKey credentials,
) async {
  await _authenticateIntoTheOldSDK(oldFuseWalletSDK, credentials);
  final exceptionOrOldWallet = await oldFuseWalletSDK.fetchWallet();

  if (exceptionOrOldWallet.hasError) {
    print("An error occurred while getting the old wallet.");
    exit(0);
  }

  final fromWalletAddress = exceptionOrOldWallet.data?.smartWalletAddress;

  if (fromWalletAddress == null) {
    print("Failed to migrate funds. fromWalletAddress is null.");
    exit(0);
  }

  return fromWalletAddress;
}

Future<void> _authenticateIntoTheOldSDK(
  FuseWalletSDK oldFuseWalletSDK,
  EthPrivateKey credentials,
) async {
  final exceptionOrJWT = await oldFuseWalletSDK.authenticate(credentials);

  if (exceptionOrJWT.hasError) {
    print("An error occurred while authenticating into the old SDK.");
    exit(0);
  }
}
