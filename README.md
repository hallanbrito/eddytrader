# EddyTrader

> **Gerenciador de perda e disciplina operacional para MetaTrader 5.**  
> Monitora o resultado da conta, encerra posições e ordens pendentes ao atingir o limite configurado e mantém a proteção ativa por um período definido.

[![MT5](https://img.shields.io/badge/MetaTrader%205-MQL5-blue)](https://www.metatrader5.com/)
![Version](https://img.shields.io/badge/version-1.0.0--rc2-orange)
![Build](https://img.shields.io/badge/build-0%20errors%20%7C%200%20warnings-brightgreen)
![Tests](https://img.shields.io/badge/regression-40%2F40%20PASS-brightgreen)

## Baixar

**Versão atual:** `1.0.0-rc2` — Release Candidate 2 (Trader UX & On-Chart Config).

- **[Abrir página de Releases](https://github.com/hallanbrito/eddytrader/releases)** — local recomendado para baixar o `EddyTrader.ex5` quando o asset binário estiver publicado.
- **[Baixar o código-fonte EddyTrader.mq5](src/EddyTrader.mq5)** — alternativa para quem prefere compilar no MetaEditor.
- **[Instalação em 2 minutos](docs/18-QUICKSTART.md)** — passo a passo direto ao ponto.

> [!IMPORTANT]
> A versão atual ainda é **Release Candidate**. O último gate de homologação, `LIVE-01`, será executado exclusivamente em conta Demo com pregão aberto antes da promoção para `v1.0.0`.

---

## O que o EddyTrader faz

Você define um limite de perda diretamente pelo gráfico ou pelos parâmetros. Exemplo:

```text
Perda máxima: 500,00 na moeda da conta
Bloqueio:     4 horas
```

Quando a perda da janela operacional atinge o limite configurado, o EddyTrader:

1. fecha todas as posições abertas da conta;
2. cancela todas as ordens pendentes;
3. mantém a conta em proteção pelo período configurado;
4. neutraliza reativamente novas posições ou ordens abertas durante o bloqueio;
5. ao final do período, cria uma nova janela operacional com baseline própria e volta ao monitoramento.

O EddyTrader atua sobre **toda a conta** — sem filtro por símbolo ou Magic Number.

### Configuração pelo Gráfico (Sem Recompilar)

Com o novo painel compacto da versão `1.0.0-rc2`, você pode alterar o limite de perda **diretamente na tela do gráfico**:

1. Clique no botão **[ CONFIGURAR ]** no HUD.
2. Digite o novo limite no campo largo da janela (ex: `750.00` ou `750,50`) e clique em **[ AVANÇAR ]** (ou tecle Enter).
3. Confira os valores na tela de confirmação e clique em **[ CONFIRMAR ]** (ou **[ VOLTAR ]** para corrigir).

O limite é atualizado e persistido imediatamente para a sua conta, mesmo que o MetaTrader seja reiniciado.

### O que ele não faz

O EddyTrader **não é uma estratégia de trading**. Ele não:

- abre operações por conta própria;
- gera sinais;
- escolhe ativos;
- define Stop Loss ou Take Profit individual;
- promete impedir fisicamente o envio de uma ordem manual;
- garante que a perda final será exatamente igual ao limite configurado.

---

## Instalação em 2 minutos

1. Baixe `EddyTrader.ex5` pela página de **Releases**. Se estiver usando o código-fonte, baixe `src/EddyTrader.mq5`.
2. No MetaTrader 5, abra **Arquivo → Abrir Pasta de Dados**.
3. Entre em `MQL5/Experts/`.
4. Cole o arquivo.
5. Se estiver usando `.mq5`, abra no MetaEditor (`F4`) e compile com `F7`.
6. No MT5, atualize **Navegador → Expert Advisors**.
7. Arraste o EddyTrader para **um único gráfico**.
8. Marque **Permitir Algo Trading** e ative o botão **Algo Trading** no MT5.

Pronto. O gráfico exibirá o painel compacto do EddyTrader com status amigável, perda monitorada, baseline e botões interativos de configuração.

➡️ Guia curto: [docs/18-QUICKSTART.md](docs/18-QUICKSTART.md)  
➡️ Manual completo: [docs/15-GUIA-OPERACIONAL.md](docs/15-GUIA-OPERACIONAL.md)

---

## Configuração recomendada

| Parâmetro | Padrão | O que significa |
|---|---:|---|
| `InpMaxLoss` | `500.0` | Limite de perda inicial da janela, na moeda da conta |
| `InpBlockDurationHours` | `4` | Duração contínua da proteção após o disparo (1 a 168h) |
| `InpHudMode` | `EDDY_HUD_COMPACT` | Modo do painel (`COMPACT`, `DETAILED`, `OFF`) |
| `InpHudCorner` | `CORNER_LEFT_UPPER` | Canto do gráfico onde o painel é exibido |
| `InpHudOffsetX` | `20` | Deslocamento horizontal do painel em pixels |
| `InpHudOffsetY` | `30` | Deslocamento vertical do painel em pixels |
| `InpTimerIntervalMs` | `500` | Frequência de monitoramento interno (ms) |
| `InpDeviationPoints` | `10` | Desvio máximo usado nos fechamentos de emergência |

### Exemplo

Se a conta estiver em BRL e:

```text
InpMaxLoss = 500
```

a proteção será acionada quando o resultado da janela atingir **-R$ 500,00 ou pior**.

> [!WARNING]
> `InpMaxLoss` é um **gatilho**, não uma garantia de perda final exata. Spread, slippage, gaps, liquidez, mercado fechado, custos e latência podem fazer o resultado final ultrapassar o limite.

---

## Como saber se está funcionando

Com o EA carregado, o HUD mostra informações como:

```text
EddyTrader v1.0.0-rc1
Estado FSM: MONITORING
Janela ativa: J0
Perda máxima: -500.00
Resultado da janela: -120.00
Posições abertas: 1
Ordens pendentes: 0
Negociação autorizada: SIM
```

Estados principais:

- **MONITORING** — monitoramento normal;
- **PROTECTION_TRIGGERED** — limite atingido;
- **LIQUIDATING** — encerrando posições/ordens;
- **BLOCKED** — proteção temporal ativa;
- **REOPENING** — preparando nova janela;
- **INIT / FAIL-CLOSED** — inicialização ou postura segura diante de inconsistência.

---

## Requisitos

- MetaTrader 5 Desktop 64-bit;
- Algo Trading habilitado;
- terminal MT5 aberto e conectado;
- apenas uma instância do EddyTrader por conta;
- nenhuma DLL, banco, Python, servidor ou serviço externo.

O EddyTrader foi homologado tecnicamente no MetaTrader 5 build 6193.

---

## Limitações importantes

- O EA só protege enquanto o terminal MT5 estiver aberto, conectado e executando o Expert Advisor.
- Em mercado fechado, uma liquidação pode permanecer em `LIQUIDATING` até a negociação voltar a ser possível.
- O MT5 não fornece ao EA um bloqueio preventivo físico para cliques manuais; durante `BLOCKED`, o EddyTrader neutraliza a exposição **reativamente**.
- A versão `1.0.0-rc1` ainda possui o gate `LIVE-01` pendente, em **Demo somente**.

---

## Status de qualidade

```text
Versão:          1.0.0-rc1
Build:           0 errors / 0 warnings
Regressão:       28 / 28 PASS
W07:             Homologado com ressalva
LIVE-01:         Pendente — DEMO ONLY
ADR 0005:        Proposed
```

Detalhes:

- [Homologação operacional W07](docs/14-HOMOLOGACAO-W07.md)
- [Checklist do Release Candidate](docs/16-RELEASE-CHECKLIST.md)
- [Release Notes 1.0.0-rc1](docs/17-RELEASE-NOTES-1.0.0-rc1.md)

---

## Para desenvolvedores e auditoria técnica

O repositório mantém toda a trilha de engenharia e decisões do projeto:

- [Manifesto](docs/00-MANIFESTO.md)
- [Visão geral](docs/01-VISAO-GERAL.md)
- [Escopo e limites](docs/02-ESCOPO-E-LIMITES.md)
- [Requisitos](docs/03-REQUISITOS.md)
- [Casos de uso](docs/04-CASOS-DE-USO.md)
- [Regras de negócio](docs/05-REGRAS-DE-NEGOCIO.md)
- [Arquitetura conceitual](docs/06-ARQUITETURA-CONCEITUAL.md)
- [MVP](docs/07-MVP.md)
- [Riscos e questões abertas](docs/08-RISCOS-E-QUESTOES-ABERTAS.md)
- [Roadmap](docs/09-ROADMAP.md)
- [Especificação matemática](docs/10-ESPECIFICACAO-MATEMATICA.md)
- [Máquina de estados](docs/11-MAQUINA-DE-ESTADOS.md)
- [Spike técnico MT5](docs/12-SPIKE-TECNICO-MT5.md)
- [Implementação do MVP](docs/13-IMPLEMENTACAO-MVP-W06.md)

### ADRs

- [ADR 0001 — Regras Temporais e Janelas de Proteção](docs/adr/0001-regras-temporais-e-janelas-de-protecao.md)
- [ADR 0002 — Composição da Perda Operacional](docs/adr/0002-composicao-da-perda-operacional.md)
- [ADR 0003 — Modelo Matemático de Janelas e Baseline](docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md)
- [ADR 0004 — Máquina de Estados e Recuperação](docs/adr/0004-maquina-de-estados-e-recuperacao.md)
- [ADR 0005 — Garantias Técnicas do MT5 e Estratégia de Recuperação](docs/adr/0005-garantias-tecnicas-mt5-e-estrategia-de-recuperacao.md)

### Build local

No Windows/PowerShell:

```powershell
./scripts/build.ps1
```

O build oficial deve terminar com:

```text
0 errors
0 warnings
```

---

## Suporte e bugs

Encontrou comportamento inesperado?

1. confira o [Quick Start](docs/18-QUICKSTART.md);
2. consulte o [Guia Operacional](docs/15-GUIA-OPERACIONAL.md);
3. abra uma [Issue no GitHub](https://github.com/hallanbrito/eddytrader/issues).

Veja também [SUPPORT.md](SUPPORT.md).

---

## Segurança operacional

Teste qualquer nova versão **primeiro em conta Demo**.

Software de gerenciamento de risco reduz riscos operacionais, mas não elimina riscos de mercado, gaps, slippage, indisponibilidade da corretora, falhas do terminal, conexão ou infraestrutura.

---

## Licença

A política de licença do projeto ainda precisa ser formalizada antes de distribuição ampla. Até que um arquivo `LICENSE` seja publicado, consulte o autor antes de redistribuir ou incorporar o EddyTrader em outros produtos.
