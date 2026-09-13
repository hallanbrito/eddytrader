//+------------------------------------------------------------------+
//|                                            persistence_probe.mq5 |
//|                                      W05 EXPERIMENTAL SPIKE      |
//|                                      NOT PRODUCTION CODE         |
//+------------------------------------------------------------------+
#property copyright "EddyTrader W05 Spike"
#property link      "https://github.com/eddytrader"
#property version   "1.00"

// Estrutura representativa de D_min_recovery (W04 / ADR 0004)
struct EddyRecoveryData
{
   int      version;
   long     account_login;
   int      current_state;       // ENUM_EDDY_STATE
   ulong    protection_event_id;
   int      window_id;           // n (0, 1, 2...)
   double   baseline;            // B_n
   datetime t_trigger;           // instante de acionamento
   datetime t_unlock;            // t_trigger + 14400s
   datetime t_updated;           // ultimo batimento cardiaco
};

input string InpAction = "TEST_WRITE"; // Opcoes: "TEST_WRITE", "TEST_READ", "CLEANUP"

#define GV_PREFIX "EDDY_"
#define STATE_FILE_NAME "eddy_recovery_state.bin"

//+------------------------------------------------------------------+
//| Testa GlobalVariables do Terminal (TECH-14)                      |
//+------------------------------------------------------------------+
void TestGlobalVariables(const EddyRecoveryData& data)
{
   Print("--- [TECH-14] TESTE DE GLOBAL VARIABLES DO TERMINAL ---");
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string prefix = StringFormat("%s%I64d_", GV_PREFIX, login);

   if(InpAction == "TEST_WRITE")
   {
      GlobalVariableSet(prefix + "STATE", (double)data.current_state);
      GlobalVariableSet(prefix + "EVENT_ID", (double)data.protection_event_id);
      GlobalVariableSet(prefix + "WINDOW_ID", (double)data.window_id);
      GlobalVariableSet(prefix + "BASELINE", data.baseline);
      GlobalVariableSet(prefix + "T_TRIGGER", (double)data.t_trigger);
      GlobalVariableSet(prefix + "T_UNLOCK", (double)data.t_unlock);
      GlobalVariableSet(prefix + "UPDATED", (double)data.t_updated);
      GlobalVariablesFlush();

      PrintFormat("[GV WRITE] Gravadas 7 variaveis com prefixo '%s'. Flush executado!", prefix);
   }
   else if(InpAction == "TEST_READ")
   {
      if(GlobalVariableCheck(prefix + "STATE"))
      {
         int state      = (int)GlobalVariableGet(prefix + "STATE");
         ulong event_id = (ulong)GlobalVariableGet(prefix + "EVENT_ID");
         int win_id     = (int)GlobalVariableGet(prefix + "WINDOW_ID");
         double base    = GlobalVariableGet(prefix + "BASELINE");
         datetime t_trg = (datetime)GlobalVariableGet(prefix + "T_TRIGGER");
         datetime t_unl = (datetime)GlobalVariableGet(prefix + "T_UNLOCK");

         PrintFormat("[GV READ] Lidas com sucesso! State: %d | EventID: %I64u | Window: %d | Baseline: %.2f | Trigger: %s | Unlock: %s",
                     state, event_id, win_id, base,
                     TimeToString(t_trg, TIME_DATE|TIME_SECONDS),
                     TimeToString(t_unl, TIME_DATE|TIME_SECONDS));
      }
      else
      {
         PrintFormat("[GV READ] Variaveis com prefixo '%s' NAO encontradas!", prefix);
      }
   }
   else if(InpAction == "CLEANUP")
   {
      GlobalVariableDel(prefix + "STATE");
      GlobalVariableDel(prefix + "EVENT_ID");
      GlobalVariableDel(prefix + "WINDOW_ID");
      GlobalVariableDel(prefix + "BASELINE");
      GlobalVariableDel(prefix + "T_TRIGGER");
      GlobalVariableDel(prefix + "T_UNLOCK");
      GlobalVariableDel(prefix + "UPDATED");
      PrintFormat("[GV CLEANUP] Removidas variaveis com prefixo '%s'", prefix);
   }
}

//+------------------------------------------------------------------+
//| Testa Arquivo Local em MQL5/Files (TECH-15)                      |
//+------------------------------------------------------------------+
void TestLocalFile(EddyRecoveryData& data)
{
   Print("--- [TECH-15] TESTE DE ARQUIVO LOCAL (MQL5/Files) ---");
   string filename = StringFormat("eddy_%I64d_state.bin", AccountInfoInteger(ACCOUNT_LOGIN));

   if(InpAction == "TEST_WRITE")
   {
      int handle = FileOpen(filename, FILE_WRITE|FILE_BIN);
      if(handle != INVALID_HANDLE)
      {
         uint written = FileWriteStruct(handle, data);
         FileFlush(handle);
         FileClose(handle);
         PrintFormat("[FILE WRITE] Gravados %u bytes no arquivo '%s' em MQL5/Files", written, filename);
      }
      else
      {
         PrintFormat("[FILE WRITE ERRO] Falha ao abrir arquivo '%s'! Erro: %d", filename, GetLastError());
      }
   }
   else if(InpAction == "TEST_READ")
   {
      if(FileIsExist(filename))
      {
         int handle = FileOpen(filename, FILE_READ|FILE_BIN);
         if(handle != INVALID_HANDLE)
         {
            EddyRecoveryData read_data;
            uint read_bytes = FileReadStruct(handle, read_data);
            FileClose(handle);

            PrintFormat("[FILE READ] Lidos %u bytes! State: %d | EventID: %I64u | Window: %d | Baseline: %.2f | Trigger: %s | Unlock: %s",
                        read_bytes, read_data.current_state, read_data.protection_event_id,
                        read_data.window_id, read_data.baseline,
                        TimeToString(read_data.t_trigger, TIME_DATE|TIME_SECONDS),
                        TimeToString(read_data.t_unlock, TIME_DATE|TIME_SECONDS));
         }
      }
      else
      {
         PrintFormat("[FILE READ] Arquivo '%s' nao existe!", filename);
      }
   }
   else if(InpAction == "CLEANUP")
   {
      if(FileIsExist(filename))
      {
         FileDelete(filename);
         PrintFormat("[FILE CLEANUP] Arquivo '%s' deletado com sucesso", filename);
      }
   }
}

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   PrintFormat("=== [W05 EXPERIMENTAL SPIKE] PERSISTENCE PROBE START (Acao: %s) ===", InpAction);

   EddyRecoveryData sample;
   sample.version             = 1;
   sample.account_login       = AccountInfoInteger(ACCOUNT_LOGIN);
   sample.current_state       = 4; // BLOCKED
   sample.protection_event_id = 10001;
   sample.window_id           = 1;
   sample.baseline            = -510.50;
   sample.t_trigger           = TimeTradeServer();
   sample.t_unlock            = sample.t_trigger + 14400; // +4 horas
   sample.t_updated           = sample.t_trigger;

   TestGlobalVariables(sample);
   TestLocalFile(sample);

   Print("=== [W05 EXPERIMENTAL SPIKE] PERSISTENCE PROBE COMPLETE ===");
}
//+------------------------------------------------------------------+
