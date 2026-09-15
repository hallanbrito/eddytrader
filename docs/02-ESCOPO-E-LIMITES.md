# 02 — Escopo e Limites do Projeto

Este documento delimita formalmente as fronteiras do **Disciplinador Trader** (nome de projeto interno: **EddyTrader**), definindo o que faz parte da entrega, o que não faz parte e o que está expressamente proibido sem decisão formal prévia.

---

## 1. Dentro do Escopo (In-Scope)

As seguintes funcionalidades e características constituem o escopo autorizado do Disciplinador Trader:

1. **Configuração de Parâmetros de Risco:**
   * Entrada parametrizada do valor monetário do limite diário de perda máxima (`InpMaxLoss`).
   * Aplicação da regra temporal normativa de bloqueio contínuo por 4 horas a partir do acionamento da proteção.
2. **Monitoramento Contínuo e Escopo Account-Global (RF-015):**
   * Monitoramento contínuo em nível global de conta, independente do ativo em que o EA esteja anexado ou do gráfico onde o trader opera.
   * Acompanhamento do resultado financeiro realizado no período diário (todas as operações de todos os símbolos e mágicas).
   * Acompanhamento do resultado financeiro flutuante (*unrealized profit/loss*) de todas as posições em aberto na conta.
   * Comparação contínua da perda acumulada relevante frente ao limite monetário configurado.
3. **Liquidação e Cancelamento de Emergência:**
   * Envio automático de requisições de fechamento a mercado para todas as posições abertas na conta (qualquer ativo, ordem manual ou de robô terceiro) quando a perda ultrapassar ou igualar o limite.
   * Envio automático de requisições de cancelamento para todas as ordens pendentes existentes na conta.
4. **Imposição e Manutenção de Bloqueio:**
   * Entrada em estado de bloqueio operacional imediatamente após a liquidação.
   * Impedimento de que novas operações ocorram durante o período de bloqueio.
   * Manutenção ininterrupta do bloqueio pelo período de 4 horas a partir do acionamento ($[t_{\text{bloqueio}}, t_{\text{bloqueio}} + 4\text{h})$).
5. **Desbloqueio e Retomada:**
   * Reconhecimento automático da conclusão das 4 horas contínuas de bloqueio no relógio do servidor.
   * Remoção do estado de bloqueio e liberação de novas operações.
   * Retomada transparente do monitoramento contínuo em nova janela via baseline de reabertura.
6. **Interface e Comunicação Local:**
   * Exibição de informações visuais claras no gráfico do MetaTrader 5 indicando o estado atual, valores de limite, posições encerradas, instante do acionamento e previsão de liberação ($t_{\text{bloqueio}} + 4\text{h}$).
   * Registro sistemático de eventos, erros e ações defensivas no Diário (*Journal*) do MetaTrader 5.
7. **Tratamento Resiliente de Erros:**
   * Registro detalhado de qualquer falha na tentativa de fechamento ou cancelamento de uma ordem/posição.
   * Continuidade do processamento das demais ordens e posições mesmo diante de falha individual.
   * Preservação da execução do EA sem interrupção catastrófica por falhas pontuais da corretora.
8. **Compatibilidade Técnica:**
   * Funcionamento pleno em contas **Demo** e contas **Real**.
   * Operação nativa exclusiva no **MetaTrader 5** via linguagem **MQL5**.
   * Funcionamento agnóstico ao ativo/símbolo negociado (índices, moedas, commodities, ações).
   * Funcionamento independente da estratégia ou método adotado pelo operador.

---

## 2. Fora do Escopo (Out-of-Scope)

Os seguintes itens **não pertencem** ao escopo do Disciplinador Trader em nenhuma de suas versões planejadas inicialmente:

1. **Abertura de Operações:** O Disciplinador Trader não abre ordens de compra ou venda no mercado.
2. **Geração de Sinais ou Análise de Mercado:** O sistema não analisa candles, indicadores, fluxo de ordens (*tape reading*), médias móveis ou notícias.
3. **Gestão de Lucro (*Take Profit* Diário):** O sistema não possui alvos de ganho, metas diárias positivas ou travas de encerramento por lucro atingido.
4. **Definição de Stop Loss ou Take Profit Inicial de Estratégia:** O EA não atua como estratégia de trading; não insere ordens com SL/TP calculados automaticamente para auferir lucros. *(Nota de Fronteira: A proteção monotônica passiva de Stop Loss definido pelo trader — impedindo afrouxamento ou remoção — foi catalogada sob o GAP-007 e autorizada exclusivamente como tema de Spike Técnico para a W11, permanecendo rigorosamente fora do escopo de implementação da W10)*.
5. **Outras Plataformas:** Não há suporte para MetaTrader 4, TradingView, NinjaTrader, ProfitChart ou qualquer outro software de negociação.
6. **Linguagens Não Nativas:** Nenhuma parte da lógica de produto será escrita em C++, C#, Python, Rust, JavaScript ou qualquer linguagem distinta de MQL5.

---

## 3. Não Autorizado sem Nova Decisão (Proibições Expressas / YAGNI Agressivo)

É expressamente proibido propor, desenhar ou implementar qualquer um dos seguintes itens sem autorização formal do proprietário do produto:

* **Estratégia de entrada ou saída:** regras para tentar auferir lucro no mercado.
* **Geração de sinais:** indicadores de compra, venda, sobrecompra ou sobrevenda.
* **Stop Loss automático ou Take Profit automático de estratégia:** regras preditivas para ancorar stops ou alvos em busca de retorno financeiro. *(A proteção defensiva de SL contra afrouxamento é tema do Spike W11 / GAP-007 e NÃO está autorizada para código na W10)*.
* **Trailing Stop preditivo:** arrasto dinâmico de stop visando maximizar ganho.
* **Martingale ou Grid:** aumento de lotes após perda ou distribuição de ordens contra a tendência.
* **Gerenciamento de lucro:** fechamento por meta financeira positiva ou trailing de patrimônio.
* **Copy Trading:** replicação de ordens para outras contas ou mestres/escravos.
* **Inteligência Artificial (IA) e Machine Learning (ML):** redes neurais, algoritmos genéticos, classificadores ou regressões.
* **APIs externas:** consumo de endpoints HTTP/REST, WebSockets, gRPC, webhooks.
* **Bibliotecas Dinâmicas (DLLs):** importação ou execução de chamadas externas via Win32 ou DLLs proprietárias.
* **Bancos de Dados:** uso de SQLite local, MySQL, PostgreSQL, Redis ou qualquer armazenamento externo complexo.
* **Painel Web ou Servidores Locais:** servidores HTTP embutidos, dashboards web, páginas HTML/CSS/JS.
* **Contêineres / Docker:** virtualização ou orquestração em contêineres.
* **Pipelines de CI/CD externos:** automações complexas de build remoto não solicitadas.
* **Serviços em Nuvem:** integração com AWS, Azure, GCP ou Firebase.
* **Telemetria Externa:** envio de dados de uso, métricas de conta ou rastreamento para servidores remotos.
* **Recursos de Monetização:** proteção contra cópia (DRM), validação de chaves de licença, travas de vencimento ou cobrança recorrente.
* **Integrações com Mensageiros:** bots de Telegram, alertas no Discord, notificações via WhatsApp, e-mails via SMTP ou SMS.

> **Regra de Ouro (YAGNI):** Se uma funcionalidade não é estritamente necessária para calcular o limite diário de perda, encerrar as ordens e posições e bloquear a conta até o horário estipulado, ela é considerada **ruído arquitetural** e está terminantemente vetada.

---

## 4. Rastreabilidade Documental

* Requisitos Decorrentes: [03 — Requisitos](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md)
* Regras de Negócio: [05 — Regras de Negócio](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md)
* Limites do MVP: [07 — MVP](file:///C:/Projetos/eddytrader/docs/07-MVP.md)
