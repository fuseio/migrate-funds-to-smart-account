import 'format.dart';

class Token {
  final String address;
  final String name;
  final String symbol;
  final BigInt amount;
  final int decimals;

  const Token({
    required this.address,
    required this.name,
    required this.symbol,
    required this.amount,
    required this.decimals,
  });

  String getBalance([withPrecision = false]) {
    return Formatter.formatValue(amount, decimals, withPrecision);
  }
}
