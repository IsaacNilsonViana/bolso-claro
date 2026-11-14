import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'finance.dart';
import 'document_parser.dart';
import 'services.dart';

final currency = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
String cash(int cents) => currency.format(cents / 100);
String monthLabel(DateTime date) =>
    DateFormat('MMMM yyyy', 'pt_BR').format(date);
String dayLabel(DateTime date) => DateFormat('dd/MM/yyyy').format(date);
const forest = Color(0xff123e36);
const mint = Color(0xffd7f4e6);
const background = Color(0xfff5f7f3);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
  await DeviceServices.init();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bolso Claro',
    debugShowCheckedModeBanner: false,
    locale: const Locale('pt', 'BR'),
    supportedLocales: const [Locale('pt', 'BR')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: forest,
        primary: forest,
        surface: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    ),
    home: const Home(),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final store = FinanceStore();
  DateTime month = monthOf(DateTime.now());
  int tab = 0;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await store.load();
    if (!mounted) return;
    setState(() => ready = true);
    await _schedule();
  }

  List<Occurrence> _upcomingOccurrences() {
    final today = DateTime.now();
    final result = <Occurrence>[];
    for (var i = 0; i < 12; i++) {
      result.addAll(store.inMonth(DateTime(today.year, today.month + i)));
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result.take(300).toList();
  }

  Future<void> _cancelUpcoming({Entry? entry}) async {
    for (final o in _upcomingOccurrences()) {
      if (entry == null || identical(o.entry, entry)) {
        await DeviceServices.cancel(o.notificationId);
      }
    }
  }

  Future<void> _schedule() async {
    if (!store.notifications) return;
    for (final o in _upcomingOccurrences()) {
      if (!o.entry.income && !o.paid) {
        await DeviceServices.remind(
          o.notificationId,
          o.title,
          o.date,
          o.cents / 100,
          daysBefore: store.reminderDays,
        );
      }
    }
  }

  Future<void> _save() async {
    await store.save();
    if (mounted) setState(() {});
  }

  Future<void> _deleteUnusedAttachments(Iterable<String?> paths) async {
    for (final path in paths.whereType<String>().toSet()) {
      final inUse = store.entries.any(
        (entry) =>
            entry.boleto == path ||
            entry.receipt == path ||
            entry.receiptByOccurrence.containsValue(path),
      );
      if (!inUse) {
        try {
          await DeviceServices.deleteAttachment(path);
        } catch (_) {
          // Legacy attachments may live outside the current private directory.
        }
      }
    }
  }

  Future<void> _toggle(Occurrence o) async {
    o.entry.paid[o.index] = !o.paid;
    if (o.paid) {
      o.entry.paidAt[o.index] = DateTime.now();
      await DeviceServices.cancel(o.notificationId);
    } else {
      o.entry.paidAt.remove(o.index);
      if (store.notifications) {
        await DeviceServices.remind(
          o.notificationId,
          o.title,
          o.date,
          o.cents / 100,
          daysBefore: store.reminderDays,
        );
      }
    }
    await _save();
  }

  Future<void> _delete(Entry e) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: Text(
          'Isso remove ${e.title} e todas as suas parcelas ou repetições.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _cancelUpcoming(entry: e);
    store.entries.remove(e);
    await _save();
    await _deleteUnusedAttachments([
      e.boleto,
      e.receipt,
      ...e.receiptByOccurrence.values,
    ]);
  }

  void _changeMonth(int offset) =>
      setState(() => month = DateTime(month.year, month.month + offset));
  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: background,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: forest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Image.asset('assets/logo.png'),
            ),
            const SizedBox(width: 10),
            const Text(
              'Bolso Claro',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ajustes',
            onPressed: () => setState(() => tab = 3),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: tab,
        children: [
          _dashboard(),
          _calendar(),
          Simulation(store: store),
          _settings(),
        ],
      ),
      floatingActionButton: tab == 3
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _form(),
              backgroundColor: forest,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Lançamento'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Início',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendário',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_graph_outlined),
            selectedIcon: Icon(Icons.auto_graph),
            label: 'Simular',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }

  Widget _monthPicker() => Row(
    children: [
      IconButton(
        onPressed: () => _changeMonth(-1),
        icon: const Icon(Icons.chevron_left),
      ),
      Expanded(
        child: Center(
          child: Text(
            monthLabel(month),
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      IconButton(
        onPressed: () => _changeMonth(1),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
  Widget _dashboard() {
    final items = store.inMonth(month);
    final income = store.total(month, true),
        expense = store.total(month, false);
    final pending = items
        .where((o) => !o.paid && !o.entry.income)
        .fold<int>(0, (s, o) => s + o.cents);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 110),
      children: [
        _monthPicker(),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: forest,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SALDO PREVISTO',
                style: TextStyle(
                  color: mint,
                  fontSize: 12,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                cash(income - expense),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _summary(
                      Icons.arrow_downward,
                      'Receitas',
                      cash(income),
                      const Color(0xffa1eac0),
                    ),
                  ),
                  Expanded(
                    child: _summary(
                      Icons.arrow_upward,
                      'Despesas',
                      cash(expense),
                      const Color(0xffffd0b9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Text(
                'A pagar: ${cash(pending)}',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Lançamentos',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            Text(
              '${items.length} no mês',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          _empty(
            'Nenhum lançamento neste mês',
            'Toque em Lançamento para começar.',
          )
        else
          ...items.map(_entryTile),
      ],
    );
  }

  Widget _summary(IconData icon, String label, String value, Color color) =>
      Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 7),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      );
  Widget _empty(String title, String subtitle) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 42),
    child: Column(
      children: [
        const Icon(Icons.inbox_outlined, color: Colors.black38, size: 42),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(subtitle, style: const TextStyle(color: Colors.black54)),
      ],
    ),
  );
  Widget _entryTile(Occurrence o) => Card(
    margin: const EdgeInsets.only(top: 9),
    child: InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => _details(o),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: o.entry.income ? mint : const Color(0xffffe9de),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                o.entry.income ? Icons.south_west : Icons.north_east,
                color: o.entry.income ? forest : const Color(0xff9b4a22),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${dayLabel(o.date)}  •  ${o.entry.category}',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  Text(
                    o.paid
                        ? (o.entry.income ? 'Recebido' : 'Pago')
                        : 'Pendente',
                    style: TextStyle(
                      color: o.paid
                          ? const Color(0xff248056)
                          : const Color(0xffa26520),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${o.entry.income ? '+' : '−'} ${cash(o.cents)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Checkbox(
                  value: o.paid,
                  onChanged: (_) => _toggle(o),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  void _details(Occurrence o) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(c).height * .82,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(
              o.title,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              '${cash(o.cents)}  •  Vence ${dayLabel(o.date)}  •  ${o.entry.category}',
            ),
            if (o.entry.recurring) const Text('Conta recorrente mensal'),
            if (o.entry.count > 1)
              Text('Parcela ${o.index + 1} de ${o.entry.count}'),
            if (o.entry.paymentDate(o.index) != null)
              Text(
                'Pago em ${dayLabel(o.entry.paymentDate(o.index)!)}',
                style: const TextStyle(
                  color: forest,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (o.entry.details.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'Detalhes',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              ...o.entry.details.map(
                (d) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(d.title),
                  subtitle: Text(
                    d.kind == 'charge'
                        ? 'Encargo'
                        : d.kind == 'discount'
                        ? 'Desconto'
                        : d.quantity > 1
                        ? '${d.quantity} itens'
                        : 'Item ou serviço',
                  ),
                  trailing: Text(
                    '${d.kind == 'discount' ? '− ' : ''}${cash(d.cents)}',
                  ),
                ),
              ),
            ],
            if (o.entry.boleto != null)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Abrir boleto'),
                onTap: () => _open(o.entry.boleto!),
              ),
            if (o.entry.receiptFor(o.index) != null)
              ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('Abrir comprovante'),
                onTap: () => _open(o.entry.receiptFor(o.index)!),
              ),
            ListTile(
              leading: const Icon(Icons.add_a_photo_outlined),
              title: Text(
                o.entry.receiptFor(o.index) == null
                    ? 'Anexar comprovante'
                    : 'Trocar comprovante',
              ),
              subtitle: const Text('Foto, Pix, ticket ou PDF'),
              onTap: () {
                Navigator.pop(c);
                _attachReceipt(o);
              },
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(c);
                await _toggle(o);
              },
              icon: Icon(o.paid ? Icons.undo : Icons.check),
              label: Text(
                o.paid
                    ? 'Marcar como pendente'
                    : o.entry.income
                    ? 'Marcar como recebido'
                    : 'Marcar como pago',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(c);
                _form(edit: o.entry);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar'),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(c);
                _delete(o.entry);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Excluir'),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _attachReceipt(Occurrence o) async {
    final path = await _selectAttachment();
    if (path == null || !mounted) return;
    DocumentAnalysis analysis;
    try {
      analysis = analyzeDocument(
        await DeviceServices.recognize(path),
        receipt: true,
      );
    } catch (_) {
      analysis = DocumentAnalysis(rawText: '');
    }
    if (!mounted) return;
    final apply = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Conferir comprovante'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!analysis.hasSuggestions)
                const Text(
                  'Não foi possível identificar os dados. O arquivo ainda pode ser anexado.',
                ),
              if (analysis.title != null) Text('Descrição: ${analysis.title}'),
              if (analysis.cents != null)
                Text('Valor identificado: ${cash(analysis.cents!)}'),
              if (analysis.paymentDate != null)
                Text('Pagamento: ${dayLabel(analysis.paymentDate!)}'),
              if (analysis.details.isNotEmpty)
                Text(
                  '${analysis.details.length} item(ns), encargo(s) ou desconto(s) identificado(s).',
                ),
              if (analysis.cents != null && analysis.cents != o.cents)
                const Text(
                  'O valor identificado difere do lançamento. Confira antes de editar o valor.',
                  style: TextStyle(color: Colors.deepOrange),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Só anexar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Aplicar dados'),
          ),
        ],
      ),
    );
    if (apply == null) {
      await DeviceServices.deleteAttachment(path);
      return;
    }
    final old = o.entry.receiptFor(o.index);
    o.entry.receiptByOccurrence[o.index] = path;
    if (apply) {
      o.entry.paid[o.index] = true;
      o.entry.paidAt[o.index] = analysis.paymentDate ?? DateTime.now();
      if (o.entry.details.isEmpty && analysis.details.isNotEmpty) {
        o.entry.details = analysis.details;
      }
      await DeviceServices.cancel(o.notificationId);
    }
    await _save();
    if (old != null) await _deleteUnusedAttachments([old]);
  }

  Future<String?> _selectAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Tirar foto'),
              subtitle: const Text('Boleto, Pix ou ticket'),
              onTap: () => Navigator.pop(c, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('Escolher arquivo'),
              subtitle: const Text('PDF ou imagem no aparelho'),
              onTap: () => Navigator.pop(c, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'camera') return DeviceServices.takePhoto();
    if (choice == 'file') return DeviceServices.attach();
    return null;
  }

  Future<void> _open(String path) async {
    try {
      await DeviceServices.open(path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o anexo.')),
        );
      }
    }
  }

  Widget _calendar() => CalendarPage(store: store, onTap: _details);
  Widget _settings() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
    children: [
      const Text(
        'Ajustes',
        style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined),
              title: const Text('Lembretes de vencimento'),
              subtitle: const Text('Notificações locais, mesmo sem internet'),
              value: store.notifications,
              onChanged: (v) async {
                store.notifications = v;
                if (!v) {
                  await _cancelUpcoming();
                } else {
                  await _schedule();
                }
                await _save();
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Avisar antes do vencimento'),
              trailing: DropdownButton<int>(
                value: store.reminderDays,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('No dia')),
                  DropdownMenuItem(value: 1, child: Text('1 dia')),
                  DropdownMenuItem(value: 2, child: Text('2 dias')),
                  DropdownMenuItem(value: 3, child: Text('3 dias')),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  store.reminderDays = v;
                  await _save();
                  await _schedule();
                },
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: const ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Privado e offline'),
          subtitle: Text(
            'Seus dados e anexos ficam apenas neste aparelho. Não é necessário criar conta.',
          ),
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        'Bolso Claro • 1.0.0',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.black45),
      ),
    ],
  );
  Future<DocumentAnalysis?> _scanAndReview(
    String path, {
    required bool receipt,
  }) async {
    DocumentAnalysis analysis;
    try {
      analysis = analyzeDocument(
        await DeviceServices.recognize(path),
        receipt: receipt,
      );
    } catch (error) {
      debugPrint('Document OCR failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Anexo salvo, mas a leitura automática falhou. Confira o arquivo.',
            ),
          ),
        );
      }
      return null;
    }
    if (!mounted) return null;
    debugPrint('Document OCR recognized ${analysis.rawText.length} characters');
    if (!analysis.hasSuggestions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum dado confiável foi identificado. Preencha manualmente.',
          ),
        ),
      );
      return null;
    }
    final apply = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Dados identificados'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (analysis.title != null) Text('Descrição: ${analysis.title}'),
              if (analysis.cents != null)
                Text('Valor: ${cash(analysis.cents!)}'),
              if (analysis.dueDate != null)
                Text('Vencimento: ${dayLabel(analysis.dueDate!)}'),
              if (analysis.paymentDate != null)
                Text('Pagamento: ${dayLabel(analysis.paymentDate!)}'),
              Text('${analysis.details.length} detalhe(s) identificado(s).'),
              ExpansionTile(
                title: const Text('Texto reconhecido'),
                tilePadding: EdgeInsets.zero,
                children: [SelectableText(analysis.rawText)],
              ),
              const SizedBox(height: 10),
              const Text(
                'Confira e corrija os campos após aplicar. A leitura de fotos pode conter erros.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Só anexar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    return apply == true ? analysis : null;
  }

  Future<FinanceDetail?> _editDetail(FinanceDetail? original) async {
    final name = TextEditingController(text: original?.title ?? '');
    final value = TextEditingController(
      text: original == null
          ? ''
          : (original.cents / 100).toStringAsFixed(2).replaceAll('.', ','),
    );
    final quantity = TextEditingController(text: '${original?.quantity ?? 1}');
    var kind = original?.kind ?? 'item';
    final result = await showDialog<FinanceDetail>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text(
            original == null ? 'Adicionar detalhe' : 'Editar detalhe',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Item, serviço ou ajuste',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Valor',
                    prefixText: 'R\$ ',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(
                      value: 'item',
                      child: Text('Item ou serviço'),
                    ),
                    DropdownMenuItem(value: 'charge', child: Text('Encargo')),
                    DropdownMenuItem(
                      value: 'discount',
                      child: Text('Desconto'),
                    ),
                  ],
                  onChanged: (v) => update(() => kind = v ?? 'item'),
                ),
                if (kind == 'item') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantidade'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final cents = parseCents(value.text);
                final qty = int.tryParse(quantity.text) ?? 1;
                if (name.text.trim().isEmpty || cents <= 0 || qty <= 0) return;
                Navigator.pop(
                  c,
                  FinanceDetail(
                    title: name.text.trim(),
                    cents: cents,
                    kind: kind,
                    quantity: kind == 'item' ? qty : 1,
                  ),
                );
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    value.dispose();
    quantity.dispose();
    return result;
  }

  Future<void> _form({Entry? edit}) async {
    final title = TextEditingController(text: edit?.title ?? '');
    final amount = TextEditingController(
      text: edit == null
          ? ''
          : (edit.cents / 100).toStringAsFixed(2).replaceAll('.', ','),
    );
    bool income = edit?.income ?? false, recurring = edit?.recurring ?? false;
    int installments = edit?.installments ?? 1;
    DateTime date = edit?.date ?? DateTime.now();
    DateTime? paymentDate = edit?.paidAt[0];
    bool markPaid = edit?.paid[0] ?? false;
    String? boleto = edit?.boleto, receipt = edit?.receipt;
    final createdPaths = <String>[];
    List<FinanceDetail> details = [...?edit?.details];
    String category = edit?.category ?? 'Outros';
    bool categoryEdited = edit != null;
    final formKey = GlobalKey<FormState>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(sheet).bottom + 20,
          ),
          child: SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheet).height * .82,
              child: Form(
                key: formKey,
                child: ListView(
                  children: [
                    Text(
                      edit == null ? 'Novo lançamento' : 'Editar lançamento',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: false,
                          label: Text('Despesa'),
                          icon: Icon(Icons.north_east),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('Receita'),
                          icon: Icon(Icons.south_west),
                        ),
                      ],
                      selected: {income},
                      onSelectionChanged: (v) => update(() {
                        income = v.first;
                        if (!categoryEdited) {
                          category = identifyCategory(title.text, income);
                        }
                      }),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: title,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Descrição',
                        hintText: 'Ex.: aluguel, salário, mercado',
                      ),
                      onChanged: (v) {
                        if (!categoryEdited) {
                          update(() => category = identifyCategory(v, income));
                        }
                      },
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'Informe uma descrição'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Valor total',
                        prefixText: 'R\$ ',
                      ),
                      validator: (v) => parseCents(v ?? '') <= 0
                          ? 'Informe um valor maior que zero'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(category),
                      initialValue: category,
                      decoration: const InputDecoration(labelText: 'Categoria'),
                      items:
                          [
                                'Alimentação',
                                'Casa',
                                'Transporte',
                                'Saúde',
                                'Assinaturas',
                                'Financeiro',
                                'Receita',
                                'Outros',
                              ]
                              .map(
                                (x) =>
                                    DropdownMenuItem(value: x, child: Text(x)),
                              )
                              .toList(),
                      onChanged: (v) => update(() {
                        category = v ?? 'Outros';
                        categoryEdited = true;
                      }),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_outlined),
                      title: const Text('Data do vencimento'),
                      subtitle: Text(dayLabel(date)),
                      trailing: const Icon(Icons.edit_calendar),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: sheet,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (d != null) update(() => date = d);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(income ? 'Recebido' : 'Pago'),
                      subtitle: const Text('Registrar a data do pagamento'),
                      value: markPaid,
                      onChanged: (v) => update(() {
                        markPaid = v;
                        paymentDate = v
                            ? (paymentDate ?? DateTime.now())
                            : null;
                      }),
                    ),
                    if (markPaid)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_available_outlined),
                        title: const Text('Data do pagamento'),
                        subtitle: Text(dayLabel(paymentDate ?? DateTime.now())),
                        trailing: const Icon(Icons.edit_calendar),
                        onTap: () async {
                          final d = await showDatePicker(
                            context: sheet,
                            initialDate: paymentDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (d != null) update(() => paymentDate = d);
                        },
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Repetir todo mês'),
                      subtitle: const Text('Continua nos meses seguintes'),
                      value: recurring,
                      onChanged: (v) => update(() => recurring = v),
                    ),
                    if (!recurring)
                      DropdownButtonFormField<int>(
                        initialValue: installments,
                        decoration: const InputDecoration(
                          labelText: 'Parcelas',
                        ),
                        items: List.generate(
                          36,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text('${i + 1}x'),
                          ),
                        ),
                        onChanged: (v) => update(() => installments = v ?? 1),
                      ),
                    const SizedBox(height: 12),
                    _attachmentButton('Boleto', boleto, () async {
                      final path = await _selectAttachment();
                      if (path != null) {
                        createdPaths.add(path);
                        final analysis = await _scanAndReview(
                          path,
                          receipt: false,
                        );
                        if (!sheet.mounted) return;
                        update(() {
                          boleto = path;
                          if (analysis?.title != null) {
                            title.text = analysis!.title!;
                          }
                          if (analysis?.cents != null) {
                            amount.text = (analysis!.cents! / 100)
                                .toStringAsFixed(2)
                                .replaceAll('.', ',');
                          }
                          if (analysis?.dueDate != null) {
                            date = analysis!.dueDate!;
                          }
                          if (analysis?.category != null) {
                            category = analysis!.category!;
                          }
                          if (analysis != null && analysis.details.isNotEmpty) {
                            details = analysis.details;
                          }
                        });
                      }
                    }, () => update(() => boleto = null)),
                    _attachmentButton('Comprovante', receipt, () async {
                      final path = await _selectAttachment();
                      if (path != null) {
                        createdPaths.add(path);
                        final analysis = await _scanAndReview(
                          path,
                          receipt: true,
                        );
                        if (!sheet.mounted) return;
                        update(() {
                          receipt = path;
                          if (analysis?.title != null) {
                            title.text = analysis!.title!;
                          }
                          if (analysis?.cents != null) {
                            amount.text = (analysis!.cents! / 100)
                                .toStringAsFixed(2)
                                .replaceAll('.', ',');
                          }
                          if (analysis?.category != null) {
                            category = analysis!.category!;
                          }
                          if (analysis?.dueDate != null) {
                            date = analysis!.dueDate!;
                          }
                          if (analysis?.paymentDate != null) {
                            paymentDate = analysis!.paymentDate!;
                            if (edit == null) date = paymentDate!;
                          }
                          if (analysis != null && analysis.details.isNotEmpty) {
                            details = analysis.details;
                          }
                          if (analysis != null) markPaid = true;
                        });
                      }
                    }, () => update(() => receipt = null)),
                    const SizedBox(height: 12),
                    const Text(
                      'Detalhes do pagamento',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'Itens, serviços, encargos e descontos',
                      style: TextStyle(color: Colors.black54),
                    ),
                    ...details.asMap().entries.map(
                      (row) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(row.value.title),
                        subtitle: Text(
                          row.value.kind == 'charge'
                              ? 'Encargo'
                              : row.value.kind == 'discount'
                              ? 'Desconto'
                              : 'Item • ${row.value.quantity}x',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(cash(row.value.cents)),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  update(() => details.removeAt(row.key)),
                            ),
                          ],
                        ),
                        onTap: () async {
                          final changed = await _editDetail(row.value);
                          if (changed != null) {
                            update(() => details[row.key] = changed);
                          }
                        },
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final added = await _editDetail(null);
                        if (added != null) update(() => details.add(added));
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar item ou ajuste'),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        final entry = Entry(
                          id: edit?.id,
                          title: title.text.trim(),
                          cents: parseCents(amount.text),
                          income: income,
                          date: date,
                          recurring: recurring,
                          installments: recurring ? 1 : installments,
                          category: category,
                          boleto: boleto,
                          receipt: receipt,
                          paid: {...?edit?.paid, 0: markPaid},
                          paidAt: {
                            ...?edit?.paidAt,
                            if (markPaid) 0: paymentDate ?? DateTime.now(),
                          },
                          receiptByOccurrence: {...?edit?.receiptByOccurrence},
                          details: details,
                        );
                        if (edit != null &&
                            receipt != null &&
                            receipt != edit.receipt) {
                          entry.receiptByOccurrence.remove(0);
                        }
                        if (!markPaid) entry.paidAt.remove(0);
                        if (markPaid) {
                          await DeviceServices.cancel(
                            Occurrence(entry, 0).notificationId,
                          );
                        }
                        if (edit == null) {
                          store.entries.add(entry);
                        } else {
                          await _cancelUpcoming(entry: edit);
                          final index = store.entries.indexOf(edit);
                          store.entries[index] = entry;
                        }
                        await _save();
                        if (edit != null) {
                          await _deleteUnusedAttachments([
                            edit.boleto,
                            edit.receipt,
                            ...edit.receiptByOccurrence.values,
                          ]);
                        }
                        await _schedule();
                        if (sheet.mounted) Navigator.pop(sheet);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('Salvar lançamento'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    title.dispose();
    amount.dispose();
    await _deleteUnusedAttachments(createdPaths);
  }

  Widget _attachmentButton(
    String label,
    String? path,
    VoidCallback add,
    VoidCallback remove,
  ) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.attach_file),
    title: Text(path == null ? 'Anexar $label' : '$label anexado'),
    subtitle: path == null
        ? null
        : Text(
            File(path).uri.pathSegments.last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
    trailing: path == null
        ? const Icon(Icons.add)
        : IconButton(onPressed: remove, icon: const Icon(Icons.close)),
    onTap: add,
  );
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, required this.store, required this.onTap});
  final FinanceStore store;
  final void Function(Occurrence) onTap;
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime selected = DateTime.now();
  @override
  Widget build(BuildContext context) {
    final day = widget.store
        .inMonth(selected)
        .where((o) => o.date.day == selected.day)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 100),
      children: [
        const Text(
          'Calendário',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Card(
          child: CalendarDatePicker(
            initialDate: selected,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            onDateChanged: (d) => setState(() => selected = d),
            onDisplayedMonthChanged: (d) => setState(
              () => selected = DateTime(
                d.year,
                d.month,
                selected.day.clamp(1, DateTime(d.year, d.month + 1, 0).day),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          dayLabel(selected),
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        if (day.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Nenhum vencimento neste dia.'),
          )
        else
          ...day.map(
            (o) => Card(
              child: ListTile(
                title: Text(o.title),
                subtitle: Text(o.paid ? 'Pago' : 'Pendente'),
                trailing: Text(cash(o.cents)),
                onTap: () => widget.onTap(o),
              ),
            ),
          ),
      ],
    );
  }
}

class Simulation extends StatefulWidget {
  const Simulation({super.key, required this.store});
  final FinanceStore store;
  @override
  State<Simulation> createState() => _SimulationState();
}

class _SimulationState extends State<Simulation> {
  final amount = TextEditingController();
  int installments = 1, start = 0, simulated = 0;
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      children: [
        const Text(
          'Simulação',
          style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
          'Veja como uma nova despesa afetaria os próximos meses, sem salvar nada.',
        ),
        const SizedBox(height: 20),
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Valor da compra',
            prefixText: 'R\$ ',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: installments,
          decoration: const InputDecoration(labelText: 'Parcelas'),
          items: List.generate(
            36,
            (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}x')),
          ),
          onChanged: (v) => setState(() => installments = v ?? 1),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: start,
          decoration: const InputDecoration(labelText: 'Primeiro mês'),
          items: List.generate(
            24,
            (i) => DropdownMenuItem(
              value: i,
              child: Text(monthLabel(DateTime(now.year, now.month + i))),
            ),
          ),
          onChanged: (v) => setState(() => start = v ?? 0),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => setState(() => simulated = parseCents(amount.text)),
          icon: const Icon(Icons.auto_graph),
          label: const Text('Calcular projeção'),
        ),
        if (simulated > 0) ...[
          const SizedBox(height: 18),
          const Text(
            'Impacto mês a mês',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          ...List.generate(installments + 3, (i) {
            final m = DateTime(now.year, now.month + start + i);
            final base =
                widget.store.total(m, true) - widget.store.total(m, false);
            final portion = i < installments
                ? simulated ~/ installments +
                      (i < simulated % installments ? 1 : 0)
                : 0;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      monthLabel(m),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text('Saldo atual: ${cash(base)}'),
                    Text('Compra: − ${cash(portion)}'),
                    const SizedBox(height: 3),
                    Text(
                      'Novo saldo: ${cash(base - portion)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: base - portion < 0
                            ? const Color(0xffaa3a35)
                            : forest,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
