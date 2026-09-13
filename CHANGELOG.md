# Changelog

Todas as mudanças relevantes do EddyTrader serão registradas neste arquivo.

O projeto segue versionamento semântico para releases públicas.

## [1.0.0-rc2] — 2026-09-13

Segundo Release Candidate do EddyTrader — W09 Trader UX & Configuração On-Chart.

### Adicionado

- painel compacto nativo no gráfico com informações voltadas ao trader (`EDDY_HUD_COMPACT`);
- configuração interativa de limite de perda diretamente pelo gráfico via botão `[ CONFIGURAR LIMITE ]`;
- modal de confirmação de alteração em dois passos para prevenir cliques acidentais;
- parser monetário tolerante a vírgulas decimais (`450,50`) e prefixos monetários (`R$`, `$`, `EUR`);
- persistência isolada por conta da configuração em `EDDY_<LOGIN>_CONFIG_MAX_LOSS`;
- precedência do limite configurado pelo trader sobre o valor padrão de `InpMaxLoss`;
- bloqueio estrito contra alterações de limite durante o período de proteção (`BLOCKED`);
- avaliação de risco imediata ao aplicar novo limite (disparo instantâneo se $W \le -L_{\text{novo}}$);
- alternância instantânea entre modo compacto e detalhado (`[ DETALHES ]` / `[ PAINEL COMPACTO ]`);
- novo parâmetro de seleção visual `InpHudMode` (`COMPACT`, `DETAILED`, `OFF`) e controle de offsets (`InpHudCorner`, `InpHudOffsetX`, `InpHudOffsetY`);
- higienização total de objetos gráficos via prefixo unificado `EddyHUD_` e limpeza no `OnDeinit`.

### Validação

- build oficial: **0 errors / 0 warnings** em todos os artefatos;
- regressão formal expandida para **40/40 PASS** (12 novos testes `W09R-01` a `W09R-12`);
- documentação e checklist atualizados.

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
