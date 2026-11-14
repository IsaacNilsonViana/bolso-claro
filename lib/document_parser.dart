import 'finance_models.dart';

class DocumentAnalysis {
  DocumentAnalysis({
    required this.rawText,
    this.title,
    this.cents,
    this.dueDate,
    this.paymentDate,
    this.category,
    List<FinanceDetail>? details,
  }) : details = details ?? [];
  final String rawText;
  final String? title;
  final int? cents;
  final DateTime? dueDate;
  final DateTime? paymentDate;
  final String? category;
  final List<FinanceDetail> details;
  bool get hasSuggestions =>
      title != null ||
      cents != null ||
      dueDate != null ||
      paymentDate != null ||
      details.isNotEmpty;
}

final _moneyPattern = RegExp(
  r'(?:R\$\s*)?(\d{1,3}(?:\.\d{3})*,\d{2}|\d+,\d{2}|\d+\.\d{2})',
  caseSensitive: false,
);
final _datePattern = RegExp(
  r'\b([0-3]?\d)[/.\-]([01]?\d)[/.\-](\d{2}|\d{4})\b',
);
final _totalLabel = RegExp(
  r'\b(total\s*(?:a\s*pagar|pago|da\s*compra)?|valor\s*(?:total|pago|do\s*documento|da\s*transa[cç][aã]o)|import[aâ]ncia\s*paga)\b',
  caseSensitive: false,
);
final _skipDetail = RegExp(
  r'total|subtotal|troco|saldo|vencimento|pagamento|documento|chave|autentica[cç][aã]o|nsu|cpf|cnpj|data|hora|pix|boleto',
  caseSensitive: false,
);
final _charge = RegExp(
  r'juros|multa|encargo|tarifa|taxa\b|frete|acr[eé]scimo',
  caseSensitive: false,
);
final _discount = RegExp(
  r'desconto|abatimento|cupom|cashback',
  caseSensitive: false,
);

DateTime? _dateIn(String text) {
  final match = _datePattern.firstMatch(text);
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  var year = int.parse(match.group(3)!);
  if (year < 100) year += 2000;
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

int? _lastMoney(String line) {
  final matches = _moneyPattern.allMatches(line).toList();
  if (matches.isEmpty) return null;
  final value = parseCents(matches.last.group(1)!);
  return value > 0 ? value : null;
}

DateTime? _labeledDate(List<String> lines, RegExp label) {
  for (var i = 0; i < lines.length; i++) {
    if (!label.hasMatch(lines[i])) continue;
    for (var j = i; j < lines.length && j <= i + 2; j++) {
      final date = _dateIn(lines[j]);
      if (date != null) return date;
    }
  }
  return null;
}

String? _merchant(List<String> lines, bool receipt) {
  final label = receipt
      ? RegExp(
          r'^(?:para|recebedor|favorecido|estabelecimento|comerciante)\s*[:\-]',
          caseSensitive: false,
        )
      : RegExp(
          r'^(?:benefici[aá]rio|cedente|prestador|empresa)\s*[:\-]',
          caseSensitive: false,
        );
  for (var i = 0; i < lines.length; i++) {
    if (!label.hasMatch(lines[i])) continue;
    final same = lines[i].replaceFirst(label, '').trim();
    if (same.length >= 3) return same;
    if (i + 1 < lines.length && lines[i + 1].length >= 3) return lines[i + 1];
  }
  for (final line in lines.take(8)) {
    if (line.length < 4 ||
        line.length > 75 ||
        !RegExp(r'[A-Za-zÀ-ÿ]{3}').hasMatch(line)) {
      continue;
    }
    if (RegExp(
      r'comprovante|boleto|pagamento|nota fiscal|cupom fiscal|recibo|pix|documento|data|hora|cnpj|cpf|banco|ag[eê]ncia|terminal|autentica',
      caseSensitive: false,
    ).hasMatch(line)) {
      continue;
    }
    if (_moneyPattern.hasMatch(line) || _datePattern.hasMatch(line)) continue;
    return line;
  }
  return null;
}

DocumentAnalysis analyzeDocument(String raw, {required bool receipt}) {
  final lines = raw
      .split(RegExp(r'[\r\n]+'))
      .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return DocumentAnalysis(rawText: raw);
  final dueDate = _labeledDate(
    lines,
    RegExp(r'vencimento|vcto|vence\b|venc\.', caseSensitive: false),
  );
  final paymentDate =
      _labeledDate(
        lines,
        RegExp(
          r'data\s*(?:do|de)?\s*pagamento|pago\s*em|pagamento\s*em|transa[cç][aã]o\s*(?:realizada|em)|data\s*da\s*transa[cç][aã]o|emitido\s*em',
          caseSensitive: false,
        ),
      ) ??
      (receipt ? lines.map(_dateIn).whereType<DateTime>().firstOrNull : null);
  int? total;
  var bestScore = -100;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!_totalLabel.hasMatch(line)) continue;
    final value =
        _lastMoney(line) ??
        (i + 1 < lines.length ? _lastMoney(lines[i + 1]) : null);
    if (value == null) continue;
    var score = 10;
    if (RegExp(
      r'valor\s*pago|total\s*pago|import[aâ]ncia\s*paga',
      caseSensitive: false,
    ).hasMatch(line)) {
      score += receipt ? 10 : 2;
    }
    if (RegExp(
      r'total\s*a\s*pagar|valor\s*do\s*documento',
      caseSensitive: false,
    ).hasMatch(line)) {
      score += receipt ? 2 : 10;
    }
    if (RegExp(
      r'subtotal|total\s*de\s*itens|total\s*bruto',
      caseSensitive: false,
    ).hasMatch(line)) {
      score -= 10;
    }
    if (score >= bestScore) {
      bestScore = score;
      total = value;
    }
  }
  final details = <FinanceDetail>[];
  for (final line in lines) {
    final amount = _lastMoney(line);
    if (amount == null) continue;
    final match = _moneyPattern.allMatches(line).last;
    final name = line
        .substring(0, match.start)
        .replaceAll(RegExp(r'[.\s:\-]+$'), '')
        .trim();
    if (_charge.hasMatch(name)) {
      details.add(
        FinanceDetail(
          title: name.isEmpty ? 'Encargo' : name,
          cents: amount,
          kind: 'charge',
        ),
      );
    } else if (_discount.hasMatch(name)) {
      details.add(
        FinanceDetail(
          title: name.isEmpty ? 'Desconto' : name,
          cents: amount,
          kind: 'discount',
        ),
      );
    } else if (name.length >= 3 &&
        !_skipDetail.hasMatch(name) &&
        RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(name)) {
      final quantityMatch = RegExp(r'\b(\d{1,3})\s*[xX]\s*').firstMatch(name);
      details.add(
        FinanceDetail(
          title: name,
          cents: amount,
          quantity: int.tryParse(quantityMatch?.group(1) ?? '') ?? 1,
        ),
      );
    }
    if (details.length >= 40) break;
  }
  final title = _merchant(lines, receipt);
  final combined = '${title ?? ''} ${lines.take(12).join(' ')}';
  var category = identifyCategory(combined, false);
  if (category == 'Outros' &&
      RegExp(
        r'supermercado|atacad[aã]o|mercearia|hortifruti',
        caseSensitive: false,
      ).hasMatch(raw)) {
    category = 'Alimentação';
  }
  return DocumentAnalysis(
    rawText: raw,
    title: title,
    cents: total,
    dueDate: dueDate,
    paymentDate: paymentDate,
    category: category,
    details: details,
  );
}
