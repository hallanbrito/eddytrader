# 21 — Release Notes do Disciplinador Trader 1.0.0-rc3

> **Identidade Pública:** Disciplinador Trader  
> **Nome de Projeto Interno / Arquivo:** EddyTrader (`src/EddyTrader.mq5`)  
> **Versão:** 1.0.0-rc3 (Release Candidate 3 — Preparada, Não Publicada)  
> **Data de Preparação:** 2026-09-14  
> **Responsável:** Agente Autônomo (Método C.H. — Work Package W10)  
> **Classificação:** Release Candidate com Identidade Pública, HUD Adaptativo e Compatibilidade Account-Global  

> [!IMPORTANT]
> **Aviso de Release:** Esta versão foi preparada formalmente na branch de trabalho `feat/disciplinador-trader-foundation`, validada em laboratório e documentada integralmente. **NENHUMA release externa foi publicada no GitHub e NENHUMA tag git foi criada**. O lançamento público permanece subordinado à autorização expressa do Product Owner.

---

## 1. Visão Geral da Versão

O **Disciplinador Trader 1.0.0-rc3** consolida a evolução de produto decorrente do feedback operacional do primeiro usuário externo ("Cobaia").

A missão central desta versão é afirmar a identidade e a finalidade do produto como um **Guardião de Disciplina Operacional em nível de Conta**, e não como um Expert Advisor convencional atrelado a estratégias de entrada ou acoplado ao gráfico onde o operador realiza suas negociações.

Principais pilares da versão:
1. **Identidade Pública "Disciplinador Trader":** Formalizada em todos os painéis visuais, logs e documentação, preservando 100% da retrocompatibilidade com chaves, scripts e arquivos legados internos.
2. **HUD Adaptativo com Minimizar/Maximizar:** Controle ergonômico da visualização gráfica com estados `PANEL_EXPANDED` e `PANEL_COLLAPSED` (pill compacta), permitindo ao trader liberar espaço gráfico instantaneamente com restauração fiel do modo preferido (`COMPACT` ou `DETAILED`).
3. **Persistência Visual Desacoplada e Segura:** O estado do HUD é salvo por conta (`EDDY_<LOGIN>_CONFIG_PANEL_COLLAPSED`) de forma estritamente não-fatal, garantindo que falhas cosméticas jamais causem *fail-closed* no motor de risco.
4. **Arquitetura Account-Global e Convivência Operacional (RF-015):** Consolidação do funcionamento independente de símbolo, gráfico e Magic Numbers, recomendando o isolamento entre o **Gráfico A** (onde o trader opera manualmente ou roda robôs terceiros) e o **Gráfico B** (onde o Disciplinador vigia a conta).
5. **Probe Laboratorial e Procedimento COMPAT-01:** Disponibilização da ferramenta `tests/probe_external_ea_w10.mq5` para testes de convivência, com travas obrigatórias contra execução em Conta Real.
6. **Fronteiras Claras e GAP-007:** Catalogação das 12 questões empíricas para o futuro Spike Técnico W11 sobre Stop Loss Monotônico, com a confirmação expressa de que **a proteção de Stop Loss NÃO foi implementada na W10**.
7. **Invariantes e Motor de Risco Intocados:** As fórmulas matemáticas de $D(t)$, $W_n(t)$, a baseline $B_n$, o bloqueio de 4 horas e as garantias de liquidação permanecem 100% íntegras.

---

## 2. Detalhamento das Mudanças da W10

### 2.1 Identidade Pública "Disciplinador Trader"
- **Painéis Visuais:**
  - HUD Compacto: Cabeçalho com o título oficial `DISCIPLINADOR TRADER`.
  - HUD Detalhado: Cabeçalho com o título oficial `DISCIPLINADOR TRADER - DETALHES`.
  - HUD Minimizado: Título condensado `DISCIPLINADOR`.
- **Logs do Sistema:**
  - Banner de inicialização no Diário (`Journal`): `Disciplinador Trader v1.0.0-rc3 inicializado com sucesso`.
- **Preservação de Legados Técnicos:**
  - O arquivo de entrada principal permanece `src/EddyTrader.mq5`;
  - O repositório e diretórios mantêm o nome `eddytrader`;
  - As Variáveis Globais mantêm o prefixo `EDDY_<LOGIN>_*`;
  - Os objetos gráficos mantêm o prefixo `EddyHUD_*`.

### 2.2 HUD Adaptativo (Minimizar / Maximizar)
- **Máquina de Estados de Apresentação:**
  - Estados: `PANEL_EXPANDED` e `PANEL_COLLAPSED`.
  - Desacoplamento estrito da FSM de risco de 6 estados.
- **Botão Minimizar `[ — MINIMIZAR ]`:**
  - Presente no canto superior direito do HUD Compacto ($H=192\text{px}$) e Detalhado ($H=340\text{px}$).
- **Pill Minimizada (`PANEL_COLLAPSED`):**
  - Dimensões ultra-compactas: $W=370\text{px}$, $H=26\text{px}$.
  - Posicionamento inteligente no canto superior esquerdo respeitando a margem do *One Click Trading* ($Y \ge 90\text{px}$).
  - Exibe título curto, status humano, resultado acumulado e limite ($D(t)$ / $-L$), além do botão de maximização `[ + ]`.
- **Segurança Visual em Bloqueio:**
  - Se a perda atingir o limite enquanto minimizado, a *pill* altera compulsoriamente seu texto para `🔒 BLOQUEADO hh:mm:ss` em contagem regressiva, com borda amarela âmbar em destaque, alertando o trader sem poluir sua visão de mercado.
- **Memória de Submodo:**
  - Alternar de Compacto -> Minimizado -> Maximizar restaura `COMPACT`.
  - Alternar de Detalhado -> Minimizado -> Maximizar restaura `DETAILED`.
- **Persistência Não-Fatal:**
  - Chave: `EDDY_<LOGIN>_CONFIG_PANEL_COLLAPSED` (`1.0` = colapsado, `0.0` = expandido).
  - Isolamento defensivo: falha de gravação ou leitura é tolerada e nunca altera `safe_to_operate`.

### 2.3 Arquitetura Account-Global e Coexistência (RF-015)
- **Operação em Nível de Conta:**
  - `CalculateFloatingResult()` utiliza `AccountInfoDouble(ACCOUNT_PROFIT)`, cobrindo todas as posições abertas na conta.
  - `CalculateRealizedResultToday()` varre todos os deals contábeis do dia do servidor em todos os símbolos e mágicas.
  - `PositionsTotal()` e `OrdersTotal()` liquidam universalmente sem filtros.
- **Topologia de Gráficos (Gráfico A vs. Gráfico B):**
  - **Gráfico A:** O trader opera com agilidade usando o painel *Chart Trade*, boletas rápidas de *One Click Trading* ou rodando outros EAs com Magic Numbers próprios.
  - **Gráfico B:** O Disciplinador Trader fica isolado em um gráfico dedicado (ex: EURUSD M1), monitorando a conta de forma independente.

### 2.4 Probe Laboratorial e Procedimento COMPAT-01
- **Artefato Criado:** `tests/probe_external_ea_w10.mq5`.
- **Características de Segurança:**
  - Recusa absoluta de inicialização em conta Real (`ACCOUNT_TRADE_MODE_REAL` gera `INIT_FAILED`);
  - Exige input explícito `InpConfirmLabExecution = true`;
  - Não executa operações automaticamente no carregamento;
  - Oferece botões manuais on-chart para Buy, BuyLimit e Clean;
  - Utiliza Magic Number isolado (`777001`).
- **Procedimento COMPAT-01:** Gate formal em Conta Demo para atestar que posições abertas pelo probe no Gráfico A são liquidadas pelo Disciplinador no Gráfico B quando a perda da conta atinge o teto.

### 2.5 Catalogação de Stop Loss e GAP-007
- Registrado formalmente em `docs/08-RISCOS-E-QUESTOES-ABERTAS.md` o **GAP-007 — Proteção Monotônica de Stop Loss (SL Lock)**.
- Mapeadas 12 perguntas de investigação empírica no MT5 para o Spike Técnico da W11.
- **Deliberação de Escopo:** O recurso de Stop Loss Lock **NÃO foi implementado na W10**, respeitando o Princípio C.H. de escopo mínimo.

---

## 3. Matriz de Testes e Validação de Qualidade

### 3.1 Regressão Formal MQL5 (`tests/test_fsm_w06.mq5`)
A suíte de testes unitários e lógicos em ambiente MetaTrader 5 foi expandida para **67 testes formais** (totalizando **68 asserções executadas** com 100% de aprovação):

| Bloco de Testes | Qtd | Descrição | Resultado |
| :--- | :---: | :--- | :---: |
| **W06** | 20 | Motor de Risco, FSM, Concorrência e CAS | **PASS (20/20)** |
| **W07R** | 6 | Reconciliação e Homologação Demo | **PASS (6/6)** |
| **W08R** | 2 | Resiliência, Hardening e Fail-Closed | **PASS (2/2)** |
| **W09R** | 29 | Trader UX, Configuração On-Chart e Submodos | **PASS (29/29)** |
| **W10R-01** | 1 | Estado inicial expandido por padrão | **PASS** |
| **W10R-02** | 1 | Transição `EXPANDED -> COLLAPSED` | **PASS** |
| **W10R-03** | 1 | Transição `COLLAPSED -> EXPANDED` | **PASS** |
| **W10R-04** | 1 | Memória de submodo `COMPACT -> COLLAPSED -> COMPACT` | **PASS** |
| **W10R-05** | 1 | Memória de submodo `DETAILED -> COLLAPSED -> DETAILED` | **PASS** |
| **W10R-06** | 1 | Persistência de `PANEL_COLLAPSED` em GlobalVariable | **PASS** |
| **W10R-07** | 1 | Restauração de `PANEL_COLLAPSED` a partir de GlobalVariable | **PASS** |
| **W10R-08** | 1 | Resiliência e desacoplamento (falha visual não gera Fail-Closed) | **PASS** |
| **W10R-09** | 1 | Preservação de invariantes da FSM durante minimização | **PASS** |
| **W10R-10** | 1 | Simulação de alerta visual na pill minimizada durante bloqueio | **PASS** |
| **TOTAL** | **67** | **Bateria de Regressão Integrada MT5** | **67/67 PASS** |

### 3.2 Validação Visual Automatizada (`tests/test_visual_w10.mq5`)
Executada no MetaTrader 5 Strategy Tester com 11 passos automatizados:
1. `Step 01`: Criação do HUD Compacto inicial;
2. `Step 02`: Detecção do botão `Hud_Btn_Min`;
3. `Step 03`: Clique em minimizar e transição para `PANEL_COLLAPSED`;
4. `Step 04`: Validação das dimensões da pill minimizada ($W=370, H=26$);
5. `Step 05`: Validação do botão de expansão `Min_Btn_Expand`;
6. `Step 06`: Clique em maximizar e restauração para `PANEL_EXPANDED` (`COMPACT`);
7. `Step 07`: Transição para `EDDY_HUD_DETAILED`;
8. `Step 08`: Clique em minimizar a partir do modo Detalhado;
9. `Step 09`: Clique em maximizar e restauração fiel do modo `DETAILED`;
10. `Step 10`: Transição para estado de bloqueio operacional;
11. `Step 11`: Validação do texto de alerta `🔒 BLOQUEADO` na pill minimizada.
**Resultado Visual:** **11/11 PASS (100% de sucesso)**.

### 3.3 Compilação Oficial (`scripts/build.ps1`)
Todos os 7 artefatos do projeto compilam com **0 errors, 0 warnings**:
1. `src/EddyTrader.mq5` (1.0.0-rc3) — **0 errors, 0 warnings**
2. `tests/test_fsm_w06.mq5` — **0 errors, 0 warnings**
3. `tests/spike_manual_block_test.mq5` — **0 errors, 0 warnings**
4. `tests/spike_hedging_liquidation_test.mq5` — **0 errors, 0 warnings**
5. `tests/spike_persistence_test.mq5` — **0 errors, 0 warnings**
6. `tests/probe_external_ea_w10.mq5` — **0 errors, 0 warnings**
7. `tests/test_visual_w10.mq5` — **0 errors, 0 warnings**

---

## 4. Status dos Gates Operacionais

| Gate | Descrição | Status | Condição de Promoção |
| :--- | :--- | :---: | :--- |
| **`LIVE-01`** | Neutralização reativa com book real em mercado aberto | **PENDENTE** | Execução exclusiva em conta Demo durante pregão ao vivo. |
| **`COMPAT-01`** | Homologação de convivência multi-ativo e robôs terceiros | **ENCERRADO COM RESSALVAS** | Evidência empírica parcial/forte no ambiente Demo observado; não implica compatibilidade universal entre corretoras, modos de conta e EAs. |
| **`GAP-007`** | Spike Técnico: Proteção Monotônica de Stop Loss | **ABERTO** | Investigação técnica em laboratório na Work Package W11. |

---

## 5. Rastreabilidade Normativa

* Requisito de Compatibilidade Account-Global: [RF-015](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-015)
* Requisito de Interface Visual HUD: [RF-014](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-014)
* Casos de Uso W10: [UC-09](file:///C:/Projetos/eddytrader/docs/04-CASOS-DE-USO.md#uc-09--ajustar-apresentacao-visual-do-hud-minimizar--maximizar) e [UC-10](file:///C:/Projetos/eddytrader/docs/04-CASOS-DE-USO.md#uc-10--coexistir-com-execucao-manual-e-eas-terceiros-em-graficos-separados)
* Regras de Negócio W10: [RN-010](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md#rn-010) e [RN-013](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md#rn-013)
* Lacunas de Especificação: [GAP-007](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md#gap-007--proteção-monotônica-de-stop-loss-sl-lock)
* Planejamento Incremental: [09 — Roadmap](file:///C:/Projetos/eddytrader/docs/09-ROADMAP.md)
* Guia de Uso: [15 — Guia Operacional](file:///C:/Projetos/eddytrader/docs/15-GUIA-OPERACIONAL.md) e [18 — Quickstart](file:///C:/Projetos/eddytrader/docs/18-QUICKSTART.md)
