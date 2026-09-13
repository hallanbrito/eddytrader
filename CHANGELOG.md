# Changelog

Todas as mudanças relevantes do EddyTrader serão registradas neste arquivo.

O projeto segue versionamento semântico para releases públicas.

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
