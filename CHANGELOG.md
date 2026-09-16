# Changelog

Todas as mudanças relevantes do EddyTrader serão registradas neste arquivo.

O projeto segue versionamento semântico para releases públicas.

## [Não publicado]

### Pesquisa (W11 — parcial)

- adicionado probe observacional Demo-only para eventos de Stop Loss, sem qualquer solicitação corretiva ou alteração no EA de produção;
- formalizada matriz das 12 questões do GAP-007 com distinção entre evidência obtida, hipótese aberta e decisão de produto pendente;
- classificação monotônica BUY/SELL validada em 7/7 casos puros;
- decisão do PO registrada: se a restauração do último SL protegido falhar, fechar imediatamente a posição por ticket para preservar o capital;
- viabilidade segura de restauração automática permanece não demonstrada; W12 continua bloqueada pelo critério de conclusão da W11.

### Corrigido (W10.3)

- HUD Compacto e Minimizado agora exibem o resultado do ciclo ativo $W=D-B_n$, iniciando visualmente em `0,00` após a reabertura;
- HUD Detalhado agora identifica explicitamente Resultado do Ciclo ($W$), Resultado do Dia ($D$) e Baseline do Ciclo ($B_n$);
- diálogo de confirmação de limite alinhado à mesma métrica de ciclo;
- resultado diário acumulado, matemática, FSM, proteção de 4 horas e persistência crítica permanecem inalterados;
- seis cenários formais `W10.3R-01..06` e três validações visuais adicionais cobrem reabertura, movimentos posteriores, preservação de $D$, proteção em `BLOCKED`, restart e coerência entre HUDs.

## [1.0.0-rc3] — 2026-09-14

Terceiro Release Candidate — W10 Fundação do Disciplinador Trader, HUD Adaptativo e Compatibilidade Account-Global.

### Adicionado

- formalização da identidade pública normativa **"Disciplinador Trader"** no cabeçalho do HUD Compacto (`DISCIPLINADOR TRADER`), HUD Detalhado (`DISCIPLINADOR TRADER - DETALHES`), pill minimizada (`DISCIPLINADOR`), logs de inicialização e documentação oficial;
- preservação total de compatibilidade técnica e legados internos: arquivo `src/EddyTrader.mq5`, prefixos de objetos `EddyHUD_*`, chaves GlobalVariables `EDDY_*` e identificadores de script;
- controle adaptativo de visualização com máquina de estados de apresentação visual (`PANEL_EXPANDED` vs `PANEL_COLLAPSED`), estritamente desacoplada da FSM operacional;
- botão de minimizar `[ — MINIMIZAR ]` integrado no cabeçalho dos painéis Compacto e Detalhado;
- modo minimizado adaptativo renderizado como *pill* compacta ($370 \times 26$ pixels) com título condensado, status operacional resumido, resultado e limite, e botão de maximização `[ + ]`;
- mecanismo de memória de submodo expandido (`g_last_expanded_hud_mode`): minimizar e maximizar restaura perfeitamente o modo preferido pelo operador (`COMPACT` ou `DETAILED`);
- alerta visual de segurança contínuo na pill minimizada durante bloqueio (`🔒 BLOQUEADO hh:mm:ss`) com destaque em amarelo âmbar e contagem regressiva em tempo real;
- persistência per-account da preferência de HUD colapsado via `EDDY_<LOGIN>_CONFIG_PANEL_COLLAPSED`, com isolamento defensivo (falhas de leitura/gravação cosmética não afetam $\mathbf{D}_{\text{min\_recovery}}$ e nunca provocam *fail-closed*);
- formalização normativa da operação e compatibilidade Account-Global ([RF-015](docs/03-REQUISITOS.md#rf-015)), garantindo independência de símbolo, gráfico e Magic Numbers;
- sonda laboratorial para validação de convivência multi-ativo e robôs terceiros (`tests/probe_external_ea_w10.mq5`) com guarda estrita contra execução em conta Real;
- especificação do procedimento de validação operacional [COMPAT-01](docs/09-ROADMAP.md#gate-compat-01--convivência-multi-ativo-e-eas-terceiros);
- catalogação formal da lacuna de especificação [GAP-007](docs/08-RISCOS-E-QUESTOES-ABERTAS.md#gap-007--proteção-monotônica-de-stop-loss-sl-lock) contendo as 12 questões empíricas para o Spike Técnico da W11 (reafirmando que a funcionalidade de SL Lock **NÃO foi implementada na W10**);
- script automatizado de teste visual `tests/test_visual_w10.mq5` validando 11 transições dinâmicas de interface no Strategy Tester.

### Corrigido (W10.2)

- correção cirúrgica do falso `FAIL-CLOSED` exibido no HUD após reinicialização/reload do EA durante estados de proteção ativos (`BLOCKED`, `LIQUIDATING`, `PROTECTION_TRIGGERED`, `REOPENING`);
- restauração explícita da saúde operacional (`g_safe_to_operate = true`) ao validar a integridade dos metadados recuperados pós-restart, assegurando que o HUD exiba `PROTEÇÃO ATIVA` (laranja) em vez de `FAIL-CLOSED` (vermelho);
- preservação estrita de todas as garantias de bloqueio operacional, rejeição de alteração de limites e neutralização reativa de intervenções manuais durante `BLOCKED`;
- preservação total de casos reais de `FAIL-CLOSED` (perda de ownership, baseline ausente em $J \ge 1$ ou erro crítico de gravação de GlobalVariables);
- adição dos testes formais `W10R-11` a `W10R-18` na suíte de regressão (elevando para 75/75 PASS);
- adição do probe automatizado `tests/probe_demo_restart_w10_2.mq5` validando os 10 passos da simulação do protocolo de recovery no Strategy Tester (sem restart empírico do EA no harness e sem ordens reais).

### Validação

- build oficial (`scripts/build.ps1`): **0 errors / 0 warnings** em todos os 9 alvos;
- bateria de regressão formal expandida para **75/75 PASS** (cobrindo `W10R-01` a `W10R-18`);
- validação visual automatizada no Strategy Tester: **11/11 PASS**;
- simulação automatizada do protocolo de recovery no Strategy Tester: **10/10 PASS** (comprova lógica/modelo do recovery; não substitui teste operacional nem executa restart real do terminal; a evidência empírica account-global decorre dos logs reais do Product Owner);
- documentação completa harmonizada sob os preceitos do Método C.H.

### Pendente

- `LIVE-01`: validação ponta a ponta da neutralização reativa em conta **Demo** com sessão de mercado aberta;
- `COMPAT-01`: homologação de convivência multi-ativo e robôs terceiros em conta **Demo**;
- `GAP-007`: execução do Spike Técnico na W11;
- promoção do ADR 0005 para `Accepted`;
- promoção de `1.0.0-rc3` para `1.0.0`.

## [1.0.0-rc2] — 2026-09-13

Segundo Release Candidate do EddyTrader — W09 Trader UX & Configuração On-Chart.

### Adicionado

- painel compacto nativo no gráfico com informações voltadas ao trader (`EDDY_HUD_COMPACT`);
- janela de configuração separada e confortável, independente do HUD de monitoramento;
- campo de texto editável largo e estável (`OBJ_EDIT`), com foco contínuo e imunidade contra reset/sobrescrita pelo timer periódico;
- suporte a tecla `Enter` (`CHARTEVENT_OBJECT_ENDEDIT`) e botões `[ AVANÇAR ]`, `[ VOLTAR ]`, `[ CONFIRMAR ]` e `[ CANCELAR ]`;
- persistência transacional estrita com gravação em GlobalVariables, flush forçado em disco e confirmação de leitura antes de mutação da variável em memória;
- parser monetário tolerante a vírgulas decimais (`450,50`), pontos (`750.25`) e prefixos monetários (`R$`, `$`, `EUR`);
- persistência isolada por conta da configuração em `EDDY_<LOGIN>_CONFIG_MAX_LOSS`;
- precedência do limite configurado pelo trader sobre o valor padrão de `InpMaxLoss`;
- bloqueio estrito contra alterações de limite durante o período de proteção (`BLOCKED`, `LIQUIDATING`, `PROTECTION_TRIGGERED`, `REOPENING`, `INIT`);
- avaliação de risco imediata ao aplicar novo limite (disparo instantâneo se $W \le -L_{\text{novo}}$);
- alternância instantânea entre modo compacto e detalhado (`[ DETALHES ]` / `[ ← VOLTAR AO RESUMO ]`);
- desobstrução vertical automática de 80px para coexistência perfeita com o painel One Click Trading (BUY/SELL) do MT5 no canto superior esquerdo;
- substituição integral de `Comment()` por painel gráfico nativo dedicado no modo detalhado (`EDDY_HUD_DETAILED`), mantendo a tela limpa e o botão de retorno sempre acessível;
- novo parâmetro de seleção visual `InpHudMode` (`COMPACT`, `DETAILED`, `OFF`) e controle de offsets (`InpHudCorner`, `InpHudOffsetX`, `InpHudOffsetY`);
- higienização total de objetos gráficos via prefixo unificado `EddyHUD_` e limpeza no `OnDeinit`.

### Validação

- build oficial: **0 errors / 0 warnings** em todos os 6 alvos;
- regressão formal expandida para **57/57 PASS** (`W06-01..20`, `W07R-01..06`, `W08R-01..02`, `W09R-01..29`);
- documentação operacional e de onboarding 100% atualizadas.

### Pendente

- `LIVE-01`: validação ponta a ponta da neutralização reativa em conta **Demo** com sessão de mercado aberta;
- promoção do ADR 0005 para `Accepted`;
- promoção de `1.0.0-rc2` para `1.0.0`.

## [1.0.0-rc1] — 2026-09-13

Primeiro Release Candidate público do EddyTrader.

### Adicionado

- gerenciamento global de limite de perda para MetaTrader 5;
- liquidação de todas as posições abertas por ticket;
- cancelamento de todas as ordens pendentes;
- proteção temporal contínua após o disparo;
- neutralização reativa durante o bloqueio;
- persistência e recuperação após restart;
- guarda atômica de instância única por conta;
- HUD operacional;
- logs estruturados e anti-flood;
- build reproduzível;
- documentação operacional e de release.

### Validação

- build: **0 errors / 0 warnings**;
- regressão formal: **28/28 PASS**;
- homologação W07 concluída com ressalva externa.

### Pendente

- `LIVE-01`: validação ponta a ponta da neutralização reativa em conta **Demo** com sessão de mercado aberta;
- promoção do ADR 0005 para `Accepted`;
- promoção de `1.0.0-rc1` para `1.0.0`.

> Este RC deve ser testado primeiro em conta Demo.
