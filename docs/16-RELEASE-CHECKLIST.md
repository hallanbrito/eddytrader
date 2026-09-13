# 16 — Checklist de Release Candidate (RC) e Critérios de Aceite

> **Versão Alvo:** EddyTrader 1.0.0-rc2  
> **Data de Auditoria:** 2026-09-13  
> **Responsável:** Agente Autônomo (Método C.H.)  
> **Status:** Release Candidate Aprovado com Gate Externo Aberto (`LIVE-01`)

---

## 1. Status dos Critérios de Liberação do Release Candidate

A tabela abaixo registra formalmente os gates de qualidade, estabilidade e conformidade arquitetural exigidos para declarar o **EddyTrader 1.0.0-rc2**:

| Item de Controle | Critério Exigido | Status | Evidência Rastreável |
| :--- | :--- | :---: | :--- |
| **Build Reproduzível** | Compilação com 0 erros e 0 warnings no MetaEditor nativo x64 (build 6193). | **APROVADO [X]** | `scripts/build.ps1` executado com 100% de sucesso em todos os artefatos de produção e teste. |
| **Regressão Formal FSM & UX** | Execução de 100% dos cenários formais automatizados no Strategy Tester. | **APROVADO [X]** | Suíte `tests/test_fsm_w06.mq5` aprovada com **40/40 PASS** (`W06-01..20`, `W07R-01..06`, `W08R-01..02` e `W09R-01..12`). |
| **Trader UX & On-Chart Config** | Painel compacto nativo, configuração interativa on-chart, parser monetário, confirmação e anti-bypass. | **APROVADO [X]** | Implementado em `src/EddyTrader.mq5`, validado nos testes `W09R-01` a `W09R-12` e higienizado com prefixo `EddyHUD_`. |
| **Hardening de Inputs** | Validação defensiva de todos os parâmetros no `OnInit()` com rejeição segura. | **APROVADO [X]** | Verificação estrita de `InpMaxLoss > 0`, `InpBlockDurationHours` (1 a 168h), `InpHudOffsets >= 0`, `InpTimerIntervalMs` (50 a 5000ms), `InpDeviationPoints` (0 a 500). |
| **Timer Defensivo** | Fallback de alta precisão e contenção com `INIT_FAILED` em falha total de timer. | **APROVADO [X]** | `EventSetMillisecondTimer` com fallback para `EventSetTimer(1)` e `INIT_FAILED` se ambos falharem. |
| **Guarda de Instância Única** | Exclusão mútua atômica via CAS sem condições de corrida na aquisição ou liberação. | **APROVADO [X]** | Protocolo CAS atômico (`0.0 -> ID`, `ID -> 0.0`), heartbeat persistido sem deleção em `OnDeinit`, timeout de 15s. |
| **Persistência de Risco** | Registro síncrono e verificação de integridade de $\mathbf{D}_{\text{min\_recovery}}$. | **APROVADO [X]** | Persistência via Global Variables de todas as 7 chaves normativas (`STATE`, `WINDOW_ID`, `BASELINE`, `T_TRIGGER`, `T_UNLOCK`, `EVENT_ID`, `DAY`), `GlobalVariablesFlush()`, retorno booleano e postura fail-closed (`safe_to_operate = false`) em falha. |
| **Logs Operacionais** | Padronização textual de níveis de log e contenção de flood em retentativas. | **APROVADO [X]** | Prefixos `[INFO]`, `[WARN]`, `[ERROR]`, `[CRITICAL]`; limitação de logs de falha repetitiva a cada 5s em `LIQUIDATING`. |
| **Auditoria de Retcodes** | Logs detalhados com ticket, símbolo, retcode numérico e descrição oficial. | **APROVADO [X]** | Auditoria implementada em `PositionClose` e `OrderDelete`. |
| **Auditoria Estática de Código** | Ausência absoluta de padrões perigosos, filtros parciais ou dependências externas. | **APROVADO [X]** | 0 ocorrências de `TODO`, `FIXME`, `HACK`, `ACCOUNT_EQUITY`, filtros de `Magic`, `PositionClose(symbol)`, `Sleep` ou `while(true)`. |
| **Isolamento de Credenciais** | Ausência de senhas, tokens, servidores ou logins fixados no código-fonte de produção. | **APROVADO [X]** | Login e servidor obtidos dinamicamente via API nativa de conta (`AccountInfoInteger`, `AccountInfoString`). |
| **Documentação Operacional** | Manual de operação, instalação, recuperação de desastres e troubleshooting. | **APROVADO [X]** | Documento [`docs/15-GUIA-OPERACIONAL.md`](15-GUIA-OPERACIONAL.md) concluído. |
| **Release Notes RC** | Especificação clara do escopo do RC, limites e avisos de risco. | **APROVADO [X]** | Documentos [`docs/17-RELEASE-NOTES-1.0.0-rc1.md`](17-RELEASE-NOTES-1.0.0-rc1.md) e [`docs/20-RELEASE-NOTES-1.0.0-rc2.md`](20-RELEASE-NOTES-1.0.0-rc2.md) concluídos. |
| **Working Tree Git Limpo** | Controle de versão higienizado, sem binários `.ex5` rastreados e sem arquivos órfãos. | **APROVADO [X]** | `.gitignore` configurado para `*.ex5`, `*.log`, `test_results.txt`. |

---

## 2. Gates Externos Pendentes para a Versão Final 1.0.0

Os itens abaixo constituem os **gates de transição** que impedem o fechamento definitivo da versão `1.0.0` final no presente momento:

| Item Pendente | Condição de Aceite | Status Atual | Justificativa Técnica |
| :--- | :--- | :---: | :--- |
| **Teste `LIVE-01`** | Execução de ordem manual e medição ponta a ponta de neutralização reativa exclusivamente em **conta Demo com pregão aberto (DEMO ONLY)**. | **PENDENTE [ ]** | Mercado financeiro fechado no final de semana da auditoria (`TRADE_RETCODE_MARKET_CLOSED = 10018`). O gate requer abertura física dos mercados. A homologação jamais exige conta Real. |
| **Aprovação do ADR 0005** | Promoção do ADR 0005 de `Proposed` para `Accepted`. | **PENDENTE [ ]** | Subordinado à evidência empírica ponta a ponta do teste `LIVE-01`. |
| **Versão Final 1.0.0** | Declaração da versão sem o sufixo `-rc2`. | **PENDENTE [ ]** | Não autorizada enquanto o gate `LIVE-01` permanecer em aberto. |
| **Tag de Release `v1.0.0`** | Criação da tag semântica no Git (`git tag v1.0.0`). | **PENDENTE [ ]** | Não autorizada nesta Work Package. |

---

## 3. Parecer Formal de Qualidade

O produto **EddyTrader 1.0.0-rc2** atende rigorosamente a todos os requisitos de robustez, engenharia de software defensiva, ergonomia operacional (Trader UX), rastreabilidade e operabilidade.

O sistema é formalmente declarado como **RELEASE CANDIDATE 2 (RC2) APROVADO COM RESSALVA EXTERNA (`LIVE-01`)**.
