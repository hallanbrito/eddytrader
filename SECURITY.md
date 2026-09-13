# Política de Segurança Operacional

O EddyTrader atua diretamente sobre posições e ordens de uma conta MetaTrader 5. Por isso, bugs que afetem proteção, liquidação ou recuperação são tratados como problemas de alta prioridade.

## O que reportar como segurança operacional

Reporte imediatamente comportamentos como:

- o limite de perda ser atingido e a proteção não disparar;
- posições permanecerem abertas quando deveriam estar em liquidação;
- ordens pendentes não serem canceladas;
- retorno indevido a `MONITORING`;
- bloqueio temporal ser encurtado ou reiniciado incorretamente;
- segunda instância assumir a conta indevidamente;
- recuperação incorreta após restart;
- neutralização durante `BLOCKED` falhar;
- persistência crítica ser ignorada.

## Como reportar

Abra uma Issue no repositório com o prefixo:

```text
[SECURITY/OPERATIONAL]
```

Inclua:

- versão do EddyTrader;
- build do MetaTrader 5;
- conta Demo/Real;
- modo Netting/Hedging;
- estado FSM;
- parâmetros;
- passos para reprodução;
- logs e retcodes relevantes.

Não publique senhas, tokens, credenciais ou informações financeiras sensíveis.

## Recomendação

Reproduza primeiro em **conta Demo**, sempre que possível.

O EddyTrader não substitui mecanismos de risco da corretora e não elimina riscos de mercado, conectividade, slippage, gaps ou indisponibilidade do terminal.
