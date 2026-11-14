# Bolso Claro

App Android de finanças pessoais, feito em Flutter para uso offline e sem conta.

## Funcionalidades

- Receitas e despesas com categoria sugerida pela descrição.
- Resumo e saldo previsto por mês.
- Contas mensais recorrentes e compras em até 36 parcelas, com arredondamento correto dos centavos.
- Pagamento individual por ocorrência, edição e exclusão.
- Calendário de vencimentos.
- Boleto e comprovante anexados separadamente; cópia guardada no armazenamento privado do app.
- Leitura de texto de imagens e PDFs anexados para sugerir título, valor, datas e detalhes do documento antes de salvar.
- Simulação de compras imediatas ou parceladas a partir de um mês futuro, sem alterar os dados.
- Lembretes locais configuráveis de 0 a 3 dias antes do vencimento.

A categoria pode ser sugerida pela descrição. Ao anexar um boleto, comprovante ou ticket, o app usa reconhecimento de texto no próprio dispositivo e apresenta os dados identificados para conferência antes de aplicá-los. A leitura de PDFs considera até cinco páginas. O resultado depende da qualidade do arquivo e pode exigir correção manual.

## Instalar no Android

[Baixar o APK mais recente](https://github.com/IsaacNilsonViana/bolso-claro/releases/latest/download/bolso-claro-v1.0.0.apk)

Baixe o arquivo no celular e abra-o para instalar. Se o Android solicitar, autorize a instalação de apps desta origem. Os registros ficam apenas no dispositivo; antes de desinstalar o aplicativo, considere que ainda não há exportação ou restauração de backup.

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
