# Changelog

Todas as mudanças relevantes do EddyTrader serão registradas neste arquivo.

O projeto segue versionamento semântico para releases públicas.

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
