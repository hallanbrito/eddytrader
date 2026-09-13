# EddyTrader — Quick Start

Este guia é para quem quer **instalar e usar**, sem precisar ler a documentação técnica do projeto.

> **Versão atual:** `1.0.0-rc2`  
> **Status:** Release Candidate — use primeiro em conta Demo.

## 1. Baixe o EddyTrader

Opção recomendada:

- abra a página de [Releases](https://github.com/hallanbrito/eddytrader/releases);
- baixe o arquivo `EddyTrader.ex5` da versão desejada.

Alternativa para desenvolvedores:

- baixe [src/EddyTrader.mq5](../src/EddyTrader.mq5);
- compile no MetaEditor com `F7`.

## 2. Instale no MetaTrader 5

1. Abra o MT5.
2. Clique em **Arquivo → Abrir Pasta de Dados**.
3. Entre em `MQL5/Experts/`.
4. Cole `EddyTrader.ex5` ou `EddyTrader.mq5`.
5. Se estiver usando `.mq5`, abra no MetaEditor e compile.
6. Volte ao MT5.
7. Abra o **Navegador** (`Ctrl+N`).
8. Clique com o botão direito em **Expert Advisors → Atualizar**.
9. Arraste **EddyTrader** para um único gráfico.
10. Ative **Permitir Algo Trading** e o botão **Algo Trading** do terminal.

## 3. Configure

Configuração inicial sugerida:

```text
InpMaxLoss            = 500.0
InpBlockDurationHours = 4
InpHudMode            = EDDY_HUD_COMPACT
InpTimerIntervalMs    = 500
InpDeviationPoints    = 10
```

`InpMaxLoss` usa a **moeda da conta**.

Exemplo:

- conta em BRL;
- `InpMaxLoss = 500`;
- proteção dispara quando a perda da janela atingir **-R$ 500 ou pior**.

## 4. Confira o Painel no Gráfico (HUD)

Depois de anexar o EA, o painel compacto exibirá diretamente no gráfico:

- **Status:** `MONITORANDO` (verde);
- **Resultado:** resultado consolidado atual do dia (ex: `+0.00 BRL`);
- **Limite Atual:** valor máximo monitorado (ex: `-500.00 BRL`);
- **Proteção:** `Vigilante` (ou contagem regressiva durante bloqueio);
- **Operações:** contagem de posições abertas e ordens pendentes;
- **Botões:** `[ CONFIGURAR ]` e `[ DETALHES ]`.

Se precisar da visualização técnica completa de engenharia com todas as variáveis matemáticas e de persistência, clique em **[ DETALHES ]** (e volte a qualquer momento clicando em **[ PAINEL COMPACTO ]**).

## 5. Como alterar o limite de perda diretamente pelo gráfico

Você não precisa abrir a janela de propriedades do robô nem recompilar:

1. No painel compacto, clique em **[ CONFIGURAR ]**.
2. Na janela dedicada, digite o novo valor no campo largo (ex: `750.00` ou `750,50`). O sistema aceita vírgulas, pontos e prefixos de moeda.
3. Clique em **[ AVANÇAR ]** (ou pressione Enter).
4. Confira os valores na tela de confirmação e clique em **[ CONFIRMAR ]** (ou **[ VOLTAR ]** para corrigir).

Pronto! O novo limite passa a valer imediatamente e fica persistido para a sua conta mesmo se o terminal for reiniciado.

> [!NOTE]
> Se o robô estiver com a proteção ativada (`PROTEÇÃO ATIVA`), a alteração de limite fica bloqueada por segurança (`[ BLOQUEADO ]`) para garantir a disciplina operacional do trader.

## 6. O que acontece quando o limite é atingido

O EddyTrader:

1. entra em proteção;
2. tenta fechar todas as posições;
3. cancela todas as ordens pendentes;
4. permanece bloqueado pelo período configurado;
5. neutraliza reativamente novas operações abertas durante o bloqueio;
6. após o prazo, cria uma nova baseline e retorna ao monitoramento quando for seguro.

## 7. Atenções importantes

- Use **uma única instância por conta**.
- Não feche o MT5 se quiser manter proteção ativa.
- Não remova o EA do gráfico durante um bloqueio.
- Se o mercado estiver fechado, a liquidação pode aguardar a reabertura.
- `MaxLoss` é gatilho, não garantia de perda final exata.
- O bloqueio de ordens manuais é reativo, não preventivo.
- Teste primeiro em **Demo**.

## 8. Precisa de mais detalhes?

- [Guia Operacional completo](15-GUIA-OPERACIONAL.md)
- [Release Notes 1.0.0-rc2](20-RELEASE-NOTES-1.0.0-rc2.md)
- [Abrir uma Issue](https://github.com/hallanbrito/eddytrader/issues)
