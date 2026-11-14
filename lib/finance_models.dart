import 'package:uuid/uuid.dart';

DateTime monthOf(DateTime d) => DateTime(d.year, d.month);
DateTime dueInMonth(DateTime start, int offset) {
  final first = DateTime(start.year, start.month + offset);
  final last = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, start.day.clamp(1, last));
}

int parseCents(String input) {
  var s = input.trim().replaceAll(RegExp(r'[^\d,.]'), '');
  if (s.isEmpty) return 0;
  final separator = s.lastIndexOf(',') > s.lastIndexOf('.') ? ',' : '.';
  if (s.contains(separator)) {
    final parts = s.split(separator);
    final decimals = parts.last;
    if (decimals.length <= 2) {
      final whole = parts
          .sublist(0, parts.length - 1)
          .join()
          .replaceAll(RegExp(r'\D'), '');
      return (int.tryParse(whole) ?? 0) * 100 +
          (int.tryParse(decimals.padRight(2, '0')) ?? 0);
    }
  }
  return (int.tryParse(s.replaceAll(RegExp(r'\D'), '')) ?? 0) * 100;
}

String identifyCategory(String text, bool income) {
  if (income) return 'Receita';
  final t = text.toLowerCase();
  if (RegExp(r'mercado|padaria|restaurante|ifood|comida|alimento')
      .hasMatch(t)) {
    return 'Alimentação';
  }
  if (RegExp(
    r'aluguel|energia|luz|água|agua|internet|condomínio|condominio|gás|gas',
  ).hasMatch(t)) {
    return 'Casa';
  }
  if (RegExp(r'uber|combustível|combustivel|gasolina|ônibus|onibus|transporte')
      .hasMatch(t)) {
    return 'Transporte';
  }
  if (RegExp(r'farmácia|farmacia|médico|medico|hospital|saúde|saude')
      .hasMatch(t)) {
    return 'Saúde';
  }
  if (RegExp(r'netflix|spotify|assinatura|streaming').hasMatch(t)) {
    return 'Assinaturas';
  }
  if (RegExp(r'cartão|cartao|boleto|banco|seguro').hasMatch(t)) {
    return 'Financeiro';
  }
  return 'Outros';
}

class FinanceDetail {
  FinanceDetail({
    required this.title,
    required this.cents,
    this.kind = 'item',
    this.quantity = 1,
  });
  String title;
  int cents;
  String kind;
  int quantity;
  Map<String, dynamic> toJson() => {
    'title': title,
    'cents': cents,
    'kind': kind,
    'quantity': quantity,
  };
  factory FinanceDetail.fromJson(Map<String, dynamic> json) => FinanceDetail(
    title: json['title'] as String? ?? '',
    cents: (json['cents'] as num?)?.toInt() ?? 0,
    kind: json['kind'] as String? ?? 'item',
    quantity: (json['quantity'] as num?)?.toInt() ?? 1,
  );
}

class Entry {
  Entry({
    String? id,
    required this.title,
    required this.cents,
    required this.income,
    required this.date,
    this.recurring = false,
    this.installments = 1,
    this.category = 'Outros',
    this.boleto,
    this.receipt,
    Map<int, bool>? paid,
    Map<int, DateTime>? paidAt,
    Map<int, String>? receiptByOccurrence,
    List<FinanceDetail>? details,
  }) : id = id ?? const Uuid().v4(),
       paid = paid ?? {},
       paidAt = paidAt ?? {},
       receiptByOccurrence = receiptByOccurrence ?? {},
       details = details ?? [];
  final String id;
  String title;
  int cents;
  bool income;
  DateTime date;
  bool recurring;
  int installments;
  String category;
  String? boleto;
  String? receipt;
  Map<int, bool> paid;
  Map<int, DateTime> paidAt;
  Map<int, String> receiptByOccurrence;
  List<FinanceDetail> details;
  int get count => recurring ? 1 : installments;
  int portion(int index) =>
      recurring ? cents : cents ~/ count + (index < cents % count ? 1 : 0);
  DateTime due(int index) => dueInMonth(date, index);
  String label(int index) => count > 1 ? '$title (${index + 1}/$count)' : title;
  bool isPaid(int index) => paid[index] ?? false;
  DateTime? paymentDate(int index) => paidAt[index];
  String? receiptFor(int index) =>
      receiptByOccurrence[index] ?? (index == 0 ? receipt : null);
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'cents': cents,
    'income': income,
    'date': date.toIso8601String(),
    'recurring': recurring,
    'installments': installments,
    'category': category,
    'boleto': boleto,
    'receipt': receipt,
    'paid': paid.map((k, v) => MapEntry('$k', v)),
    'paidAt': paidAt.map((k, v) => MapEntry('$k', v.toIso8601String())),
    'receiptByOccurrence': receiptByOccurrence.map((k, v) => MapEntry('$k', v)),
    'details': details.map((d) => d.toJson()).toList(),
  };
  factory Entry.fromJson(Map<String, dynamic> json) => Entry(
    id: '${json['id']}',
    title: json['title'] as String,
    cents: (json['cents'] as num).toInt(),
    income: json['income'] as bool,
    date: DateTime.parse(json['date'] as String),
    recurring: json['recurring'] == true,
    installments: (json['installments'] as num?)?.toInt() ?? 1,
    category: json['category'] as String? ?? 'Outros',
    boleto: json['boleto'] as String?,
    receipt: json['receipt'] as String?,
    paid: (json['paid'] as Map? ?? {}).map(
      (k, v) => MapEntry(int.parse('$k'), v == true),
    ),
    paidAt: (json['paidAt'] as Map? ?? {}).map(
      (k, v) => MapEntry(int.parse('$k'), DateTime.parse('$v')),
    ),
    receiptByOccurrence: (json['receiptByOccurrence'] as Map? ?? {}).map(
      (k, v) => MapEntry(int.parse('$k'), '$v'),
    ),
    details: (json['details'] as List? ?? [])
        .map((d) => FinanceDetail.fromJson(Map<String, dynamic>.from(d)))
        .toList(),
  );
}

class Occurrence {
  Occurrence(this.entry, this.index);
  final Entry entry;
  final int index;
  DateTime get date => entry.due(index);
  int get cents => entry.portion(index);
  bool get paid => entry.isPaid(index);
  String get title => entry.label(index);
  int get notificationId => ('${entry.id}:$index').codeUnits.fold<int>(
    0,
    (h, c) => (h * 31 + c) & 0x7fffffff,
  );
}
