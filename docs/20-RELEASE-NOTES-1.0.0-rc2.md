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
  - **Status Operacional em Linguagem Amigável:** `MONITORANDO` (verde), `PROTEÇÃO ACIONADA` / `FECHANDO OPERAÇÕES` (vermelho), `PROTEÇÃO ATIVA` (laranja), ou `FAIL-CLOSED` (vermelho de alerta).
  - **Limite de Perda Efetivo:** Valor atualizado em tempo real na moeda da conta.
  - **Perda da Janela ($W$):** Resultado financeiro da janela de monitoramento atual com coloração dinâmica por severidade.
  - **Total Consolidado do Dia ($D$):** Resultado consolidado diário ($R_{\text{day}} + F(t)$).
  - **Tempo Restante de Proteção:** Contagem regressiva precisa em horas, minutos e segundos (`hh:mm:ss`) durante contenção ou bloqueio ativo.
  - **Botão `[ CONFIGURAR LIMITE ]`:** Acesso imediato à edição do limite sem abrir menus do MT5.
  - **Botão `[ DETALHES ]`:** Alternância com um clique para a visualização técnica completa de auditoria via comentário do gráfico.

### 2.2 Configuração de Limite pelo Gráfico com Confirmação em Dois Passos
- **Janela Modal Integrada:** Clicar em `[ CONFIGURAR LIMITE ]` abre uma caixa de edição sobre o gráfico com o limite atual e campo para novo valor.
- **Parser Monetário Flexível e Tolerante:**
  - Aceita tanto ponto quanto vírgula como separador decimal (ex: `450.50` ou `450,50`);
  - Suporta prefixos monetários comuns (`R$ 350,00`, `$ 500`, `EUR 250`);
  - Remove espaços e caracteres espúrios;
  - Rejeita estritamente valores nulos (`0`), negativos ou textos sem dígitos válidos, exibindo mensagem de erro clara no próprio painel.
- **Confirmação Explícita de Segurança:** Exibe tela de confirmação (`De R$ 500,00 para R$ 600,00?`) antes de persistir, evitando cliques acidentais.
- **Avaliação Imediata de Risco:** Ao confirmar um limite mais rigoroso que a perda atual da janela ($W \le -L_{\text{novo}}$), o sistema dispara a transição de proteção no mesmo ciclo, sem depender da chegada de um próximo tick de mercado.

### 2.3 Salvaguardas Rígidas de Risco ("Anti-Cheat / Anti-Bypass")
- **Bloqueio de Edição Durante a Proteção:** Enquanto o EA estiver em `BLOCKED`, `LIQUIDATING` ou `PROTECTION_TRIGGERED`, o botão de configuração exibe `[ LIMITE BLOQUEADO ]` e qualquer tentativa de alterar o limite é sumariamente rejeitada pelo motor, garantindo que o trader não relaxe o limite para driblar a disciplina de bloqueio.
- **Proteção contra Falhas (Fail-Closed):** Se o ambiente estiver em fail-closed (`safe_to_operate == false` ou perda de ownership), qualquer solicitação de configuração é imediatamente rejeitada.
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
| **Interface (UX)** | `InpHudOffsetY` | `int` | `30` | Deslocamento vertical do painel em pixels ($\ge 0$). |
| **Operacional** | `InpTimerIntervalMs` | `int` | `500` | Intervalo de varredura do timer em milissegundos (50 a 5000ms). |
| **Operacional** | `InpDeviationPoints` | `ulong` | `10` | Slippage/desvio máximo tolerado na liquidação (pontos). |

---

## 4. Status da Bateria de Testes Automatizada

A suíte formal de regressão (`tests/test_fsm_w06.mq5`) foi expandida de 28 para **40 cenários automatizados**, cobrindo exaustivamente todas as novas regras de UX e persistência:

| Grupo de Testes | Quantidade | Cenários | Status |
| :--- | :---: | :--- | :---: |
| **FSM e Reconstituição Básica** | 15 | `W06-01` a `W06-15` | **APROVADO (15/15)** |
| **Concorrência e Instance Guard** | 5 | `W06-16` a `W06-20` | **APROVADO (5/5)** |
| **Reconciliação e Homologação W07** | 6 | `W07R-01` a `W07R-06` | **APROVADO (6/6)** |
| **Resiliência e Fail-Closed W08** | 2 | `W08R-01` a `W08R-02` | **APROVADO (2/2)** |
| **Trader UX, Parsing e Precedência W09** | 12 | `W09R-01` a `W09R-12` | **APROVADO (12/12)** |
| **TOTAL GERAL** | **40** | **100% da Bateria de Regressão** | **40/40 PASS** |

### Resumo dos Novos Cenários W09R:
- **W09R-01:** Precedência de configuração persistida sobre `InpMaxLoss` na inicialização;
- **W09R-02:** Fallback fiel para `InpMaxLoss` na ausência de GlobalVariables;
- **W09R-03:** Atualização bem-sucedida de limite em `MONITORING` com ambiente seguro;
- **W09R-04:** Rejeição estrita de alteração durante `BLOCKED` e preservação dos parâmetros temporais de bloqueio;
- **W09R-05:** Rejeição estrita de alteração sob ambiente fail-closed (`safe_to_operate = false`);
- **W09R-06:** Validação e rejeição de valores nulos ou negativos ($\le 0$);
- **W09R-07:** Validação e rejeição de entradas de texto e strings vazias;
- **W09R-08:** Parsing de valores decimais com vírgula (ex: `"450,50"` $\rightarrow 450.50$);
- **W09R-09:** Parsing e higienização de prefixos monetários (`R$`, `$`, `EUR`) e espaços;
- **W09R-10:** Disparo imediato da transição de proteção caso o novo limite seja mais rigoroso que a perda corrente;
- **W09R-11:** Isolamento estrito das chaves de configuração por login de conta;
- **W09R-12:** Limpeza seletiva com prefixo `EddyHUD_` sem violar objetos gráficos do usuário.

---

## 5. Status do Gate de Homologação Externa LIVE-01

O gate externo **`LIVE-01`** (medição empírica de latência da neutralização reativa com intervenções manuais ponta a ponta) permanece classificado como **PENDENTE**, subordinado exclusivamente à abertura física dos mercados em ambiente de **CONTA DEMO**:

> [!IMPORTANT]
> - O EddyTrader 1.0.0-rc2 é recomendado para testes e homologação operacional **exclusivamente em conta Demo**.
> - A promoção final para `v1.0.0` ocorrerá após a execução do teste `LIVE-01` em pregão aberto.
