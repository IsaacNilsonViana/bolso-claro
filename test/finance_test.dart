import 'package:bolso_claro/finance.dart';
import 'package:bolso_claro/document_parser.dart';
import 'package:bolso_claro/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app starts with local finance features', () {
    expect(const App(), isA<App>());
  });
  test('money parsing keeps cents', () {
    expect(parseCents('R\$ 1.234,56'), 123456);
    expect(parseCents('10,5'), 1050);
  });
  test('installments preserve the full amount', () {
    final entry = Entry(
      title: 'Compra',
      cents: 1000,
      income: false,
      date: DateTime(2026, 1, 31),
      installments: 3,
    );
    expect(List.generate(3, entry.portion).reduce((a, b) => a + b), 1000);
    expect(entry.due(1), DateTime(2026, 2, 28));
  });
  test('recurring entries continue and payment stays per month', () {
    final store = FinanceStore();
    final entry = Entry(
      title: 'Aluguel',
      cents: 100000,
      income: false,
      date: DateTime(2026, 1, 10),
      recurring: true,
      paid: {0: true},
    );
    store.entries.add(entry);
    expect(store.inMonth(DateTime(2026, 1)).single.paid, true);
    expect(store.inMonth(DateTime(2027, 1)).single.paid, false);
    expect(store.total(DateTime(2027, 1), false), 100000);
  });
  test('category suggestion recognizes common expenses', () {
    expect(identifyCategory('Mercado Central', false), 'Alimentação');
  });
  test('boleto extracts amount, due date, service and charges', () {
    final result = analyzeDocument('''
BENEFICIÁRIO: Energia Sul
VENCIMENTO 15/12/2026
Consumo de energia 110,00
Juros 2,50
Desconto 5,00
VALOR TOTAL A PAGAR R\$ 107,50
''', receipt: false);
    expect(result.title, 'Energia Sul');
    expect(result.cents, 10750);
    expect(result.dueDate, DateTime(2026, 12, 15));
    expect(result.category, 'Casa');
    expect(result.details.where((d) => d.kind == 'charge').single.cents, 250);
    expect(result.details.where((d) => d.kind == 'discount').single.cents, 500);
  });
  test('pix proof extracts paid amount and payment date', () {
    final result = analyzeDocument('''
Comprovante Pix
Para: Padaria da Praça
Data do pagamento: 11/11/2026
Valor pago R\$ 23,90
''', receipt: true);
    expect(result.title, 'Padaria da Praça');
    expect(result.cents, 2390);
    expect(result.paymentDate, DateTime(2026, 11, 11));
    expect(result.category, 'Alimentação');
  });
  test('market ticket extracts item prices and total', () {
    final result = analyzeDocument('''
Supermercado Bom Preço
Arroz 1 x 8,50
Leite 2 x 4,00 8,00
DESCONTO 1,50
TOTAL 15,00
11/11/2026
''', receipt: true);
    expect(result.cents, 1500);
    expect(result.details.where((d) => d.kind == 'item').length, 2);
    expect(result.details.where((d) => d.kind == 'discount').single.cents, 150);
    expect(result.paymentDate, DateTime(2026, 11, 11));
  });
}
