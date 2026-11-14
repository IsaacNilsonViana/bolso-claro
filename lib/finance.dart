import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'finance_models.dart';
export 'finance_models.dart';

class FinanceStore {
  final List<Entry> entries = [];
  bool notifications = true;
  int reminderDays = 1;
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    notifications = p.getBool('notifications') ?? true;
    reminderDays = p.getInt('reminderDays') ?? 1;
    final saved = p.getString('finance_entries');
    if (saved != null) {
      entries.addAll(
        (jsonDecode(saved) as List).map(
          (e) => Entry.fromJson(Map<String, dynamic>.from(e)),
        ),
      );
    } else {
      final legacy = p.getString('entries');
      if (legacy != null) {
        for (final item in jsonDecode(legacy) as List) {
          final e = Map<String, dynamic>.from(item);
          entries.add(
            Entry(
              title: e['title'] as String,
              cents: ((e['amount'] as num) * 100).round(),
              income: e['income'] == true,
              date: DateTime.parse(e['date'] as String),
              category: e['category'] as String? ?? 'Outros',
              boleto: e['attachment'] as String?,
              paid: {0: e['paid'] == true},
            ),
          );
        }
        await save();
      }
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'finance_entries',
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
    await p.setBool('notifications', notifications);
    await p.setInt('reminderDays', reminderDays);
  }

  List<Occurrence> inMonth(DateTime month) {
    final result = <Occurrence>[];
    for (final e in entries) {
      final offset =
          (month.year - e.date.year) * 12 + month.month - e.date.month;
      if (offset < 0 || (!e.recurring && offset >= e.count)) continue;
      result.add(Occurrence(e, offset));
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  int total(DateTime month, bool income) =>
      inMonth(month)
          .where((o) => o.entry.income == income)
          .fold(0, (sum, o) => sum + o.cents);
}
