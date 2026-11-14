# Bolso Claro

App Android de finanças pessoais, feito em Flutter para uso offline e sem conta.

## Funcionalidades

- Receitas e despesas com categoria sugerida pela descrição.
- Resumo e saldo previsto por mês.
- Contas mensais recorrentes e compras em até 36 parcelas, com arredondamento correto dos centavos.
- Pagamento individual por ocorrência, edição e exclusão.
- Calendário de vencimentos.
- Boleto e comprovante anexados separadamente; cópia guardada no armazenamento privado do app.
- Simulação de compras imediatas ou parceladas a partir de um mês futuro, sem alterar os dados.
- Lembretes locais configuráveis de 0 a 3 dias antes do vencimento.

A identificação automática atual sugere a categoria a partir da descrição e pode sugerir um título pelo nome do arquivo anexado. **O app ainda não extrai dados do conteúdo de boletos por OCR.**

## Desenvolvimento

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

O APK de release usa a chave de debug do projeto. Para distribuição pública, configure uma chave de assinatura própria.

Os registros são salvos em SharedPreferences e os anexos em arquivos privados do aplicativo. A desinstalação pode apagar ambos. Ainda não há exportação ou restauração de backup.
