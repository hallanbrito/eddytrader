# 20 — Release Notes do EddyTrader 1.0.0-rc2

> **Versão:** EddyTrader 1.0.0-rc2 (Release Candidate 2)  
> **Data de Publicação:** 2026-09-13  
> **Responsável:** Agente Autônomo (Método C.H. — Work Package W09)  
> **Classificação:** Release Candidate Operacional com Foco em Trader UX

---

## 1. Visão Geral da Versão

O **EddyTrader 1.0.0-rc2** é a segunda versão Release Candidate do EddyTrader, introduzindo uma camada moderna e ergonômica de **Trader UX** sobre o motor autônomo de proteção de capital consolidado na versão `1.0.0-rc1`.

Esta versão transforma a experiência de uso: o operador/trader não precisa mais abrir caixas de diálogo técnicas de propriedades, navegar por parâmetros complexos de engenharia ou recompilar o código para ajustar o limite de perda. O monitoramento e o ajuste do limite agora são realizados **diretamente sobre o gráfico do MetaTrader 5**, através de um painel compacto, interativo e visualmente elegante.

Todas as garantias fundamentais de segurança, integridade matemática, FSM normativa de 6 estados, liquidação compulsória integral, bloqueio contínuo de 4 horas, guarda atômica de instância por conta e postura fail-closed foram **100% preservadas e blindadas contra qualquer violação**.

---

## 2. O que Mudou no 1.0.0-rc2 (W09 Trader UX)

### 2.1 Painel Compacto Interativo no Gráfico (HUD)
- **Modo Padrão Compacto (`EDDY_HUD_COMPACT`):** Interface nativa em formato de cartão escuro (tema profissional de trading), exibindo com clareza imediata:
  - **Status Operacional em Linguagem Amigável:** `MONITORANDO` (verde), `PROTEÇÃO ACIONADA` / `FECHANDO OPERAÇÕES` (vermelho), `PROTEÇÃO ATIVA` (laranja), `REABRINDO` (ouro) ou `FAIL-CLOSED` (vermelho de alerta).
  - **Resultado Atual:** Resultado financeiro consolidado do dia na moeda da conta com cor dinâmica.
  - **Limite de Perda Efetivo:** Valor vigente na moeda da conta (ex: `-500.00 BRL`).
  - **Proteção / Tempo Restante:** `Vigilante` em operação normal ou contagem regressiva precisa (`Bloqueio: hh:mm:ss`) durante contenção ou bloqueio ativo.
  - **Operações:** Posições abertas e ordens pendentes atuais (ex: `0 pos / 0 ord`).
  - **Botão `[ CONFIGURAR ]`:** Acesso imediato à janela dedicada de configuração on-chart sem abrir menus do MT5 (ou `[ BLOQUEADO ]` sob proteção ativa).
  - **Botão `[ DETALHES ]`:** Alternância com um clique para o painel técnico gráfico dedicado nativo (sem uso de `Comment()`).

### 2.2 Janela Separada de Configuração e Digitação Real Estável
- **Painel Dedicado Independente:** Clicar em `[ CONFIGURAR ]` abre uma janela confortável e espaçosa posicionada estrategicamente no gráfico, mantendo o painel principal de monitoramento 100% visível.
- **Campo de Edição Estável e Focado:**
  - O campo de texto largo (`OBJ_EDIT`) mantém o foco de digitação e preserva os caracteres inseridos pelo operador;
  - O loop de varredura periódica da FSM / timer (500 ms) não destrói, não recria e não sobrescreve o texto em digitação.
- **Parser Monetário Flexível e Tolerante:**
  - Aceita tanto ponto quanto vírgula como separador decimal (ex: `450.50` ou `450,50`);
  - Suporta prefixos monetários comuns (`R$ 350,00`, `$ 500`, `EUR 250`);
  - Remove espaços e caracteres espúrios;
  - Rejeita estritamente valores nulos (`0`), negativos ou textos sem dígitos válidos, exibindo mensagem de erro clara no próprio painel.
- **Confirmação Explícita de Segurança em Dois Passos:**
  - O operador avança clicando em `[ AVANÇAR ]` ou pressionando `Enter`;
  - A tela de confirmação exibe: Limite Atual, Novo Limite, Resultado Atual, Aviso de aplicação imediata, e botões `[ VOLTAR ]` e `[ CONFIRMAR ]`;
  - Clicar em `[ CANCELAR ]` fecha a janela sem qualquer alteração de limite ou persistência em disco.
- **Avaliação Imediata de Risco:** Ao confirmar um limite mais rigoroso que a perda atual da janela ($W \le -L_{\text{novo}}$), o sistema dispara a transição de proteção no mesmo ciclo, sem depender da chegada de um próximo tick de mercado.

### 2.3 Salvaguardas Rígidas de Risco ("Anti-Cheat / Anti-Bypass")
- **Bloqueio de Edição Durante a Proteção:** Enquanto o EA estiver em `BLOCKED`, `LIQUIDATING` ou `PROTECTION_TRIGGERED`, o botão de configuração exibe `[ BLOQUEADO ]` e qualquer tentativa de alterar o limite é sumariamente rejeitada pelo motor, garantindo que o trader não relaxe o limite para driblar a disciplina de bloqueio.
- **Proteção contra Falhas (Fail-Closed):** Se o ambiente estiver em fail-closed (`safe_to_operate == false` ou perda de ownership), qualquer solicitação de configuração é imediatamente rejeitada e qualquer janela aberta é sumariamente encerrada.
- **Preservação de Invariantes de Bloqueio:** Tentativas de alteração de limite durante o bloqueio jamais alteram os tempos já formalizados ($t_{\text{trigger}}$, $t_{\text{unlock}}$) ou o `protection_event_id`.

### 2.4 Precedência e Isolamento de Configuração Persistida
- **Precedência Normativa:** Na inicialização (`OnInit`), o EddyTrader busca a chave `EDDY_<LOGIN>_CONFIG_MAX_LOSS` nas Variáveis Globais do terminal. Se existir e for válida ($> 0$), assume esse valor com precedência sobre o input padrão `InpMaxLoss`.
- **Fallback Automático:** Caso não haja configuração persistida prévia ou ela seja inválida, adota o valor configurado em `InpMaxLoss`.
- **Isolamento Estrito por Conta:** Chaves isoladas pelo identificador da conta (`g_account_login`), impedindo interferência cruzada entre contas diferentes abertas no mesmo terminal.

### 2.5 Limpeza e Higienização Gráfica Total
- Todos os objetos visuais são gerados com o prefixo unificado `#define EDDY_UI_PREFIX "EddyHUD_"`.
- No evento de descarregamento (`OnDeinit`), `UI_DeleteAll()` e `Comment("")` removem 100% dos objetos gráficos criados pelo EddyTrader, sem tocar em desenhos manuais ou objetos externos do trader no gráfico.

---

## 3. Matriz de Parâmetros de Entrada Atualizada

| Grupo | Parâmetro | Tipo | Padrão | Descrição |
| :--- | :--- | :---: | :---: | :--- |
| **Risco** | `InpMaxLoss` | `double` | `500.0` | Limite de perda inicial padrão (moeda da conta, $> 0.0$). |
| **Risco** | `InpBlockDurationHours` | `int` | `4` | Duração contínua do bloqueio temporal (1 a 168h). |
| **Interface (UX)** | `InpHudMode` | `enum` | `EDDY_HUD_COMPACT` | Modo visual (`EDDY_HUD_COMPACT`, `EDDY_HUD_DETAILED`, `EDDY_HUD_OFF`). |
| **Interface (UX)** | `InpHudCorner` | `enum` | `CORNER_LEFT_UPPER` | Canto de ancoragem do HUD no gráfico do MT5. |
| **Interface (UX)** | `InpHudOffsetX` | `int` | `20` | Deslocamento horizontal do painel em pixels ($\ge 0$). |
| **Interface (UX)** | `InpHudOffsetY` | `int` | `10` | Deslocamento vertical adicional em pixels ($\ge 0$, com reserva automática de 80px abaixo do One Click Trading no canto superior esquerdo). |
| **Operacional** | `InpTimerIntervalMs` | `int` | `500` | Intervalo de varredura do timer em milissegundos (50 a 5000ms). |
| **Operacional** | `InpDeviationPoints` | `ulong` | `10` | Slippage/desvio máximo tolerado na liquidação (pontos). |

---

## 4. Status da Bateria de Testes Automatizada

A suíte formal de regressão (`tests/test_fsm_w06.mq5`) conta com **57 cenários automatizados**, cobrindo exaustivamente todas as regras de proteção, concorrência, tolerância a falhas e Trader UX:

| Grupo de Testes | Quantidade | Cenários | Status |
| :--- | :---: | :--- | :---: |
| **FSM e Reconstituição Básica** | 15 | `W06-01` a `W06-15` | **APROVADO (15/15)** |
| **Concorrência e Instance Guard** | 5 | `W06-16` a `W06-20` | **APROVADO (5/5)** |
| **Reconciliação e Homologação W07** | 6 | `W07R-01` a `W07R-06` | **APROVADO (6/6)** |
| **Resiliência e Fail-Closed W08** | 2 | `W08R-01` a `W08R-02` | **APROVADO (2/2)** |
| **Trader UX, Parsing e Precedência W09** | 12 | `W09R-01` a `W09R-12` | **APROVADO (12/12)** |
| **Persistência Transacional e Salvaguardas W09.1** | 7 | `W09R-13` a `W09R-19` | **APROVADO (7/7)** |
| **Estabilidade de Edição e Fluxo Trader UX W09.2** | 5 | `W09R-20` a `W09R-24` | **APROVADO (5/5)** |
| **Layout One Click Trading e Detalhes Reversível W09.3** | 5 | `W09R-25` a `W09R-29` | **APROVADO (5/5)** |
| **TOTAL GERAL** | **57** | **100% da Bateria de Regressão** | **57/57 PASS** |

### Resumo dos Cenários W09R-25 a W09R-29 (W09.3):
- **W09R-25:** Transição COMPACT -> DETAILED altera exclusivamente `g_hud_mode` sem afetar `g_max_loss` ou FSM;
- **W09R-26:** Clique em `[ ← VOLTAR AO RESUMO ]` no painel detalhado restaura com sucesso `EDDY_HUD_COMPACT`;
- **W09R-27:** Alternância contínua de modos visuais preserva integralmente `t_trigger`, `t_unlock`, `event_id`, `baseline` e `window_id`;
- **W09R-28:** Abrir DETALHES fecha de maneira segura qualquer diálogo de configuração sem aplicar valor pendente;
- **W09R-29:** Retorno ao modo COMPACT restaura a disponibilidade do botão `[ CONFIGURAR ]` sob `MONITORING` seguro e bloqueia sob fail-closed.

---

## 5. Status do Gate de Homologação Externa LIVE-01

O gate externo **`LIVE-01`** (medição empírica de latência da neutralização reativa com intervenções manuais ponta a ponta) permanece classificado como **PENDENTE**, subordinado exclusivamente à abertura física dos mercados em ambiente de **CONTA DEMO**:

> [!IMPORTANT]
> - O EddyTrader 1.0.0-rc2 é recomendado para testes e homologação operacional **exclusivamente em conta Demo**.
> - A promoção final para `v1.0.0` ocorrerá após a execução do teste `LIVE-01` em pregão aberto.
