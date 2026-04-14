//+------------------------------------------------------------------+
//|                                          FundedRulesManager.mqh  |
//|                        Copyright 2024, Nkondog Anselme Venceslas |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Enforces prop firm challenge rules:                               |
//|   - Daily drawdown limit (e.g. 5%)                               |
//|   - Overall max drawdown from peak / initial (e.g. 10%)          |
//|   - Profit target tracker (e.g. 8%)                              |
//|   - Optional consistency rule                                    |
//| State is persisted via MT5 GlobalVariables so it survives        |
//| EA restarts and platform reboots.                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nkondog Anselme Venceslas"
#property link      "https://www.mql5.com"

CTrade g_fundedTrade;  // Separate CTrade instance for emergency closes

//+------------------------------------------------------------------+
//| Close all positions opened by this EA on the current symbol      |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
  {
   Print("PropPasserEA [FundedRules]: Closing all positions — ", reason);
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == gSymbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
           {
            if(!g_fundedTrade.PositionClose(ticket))
               Print("PropPasserEA [FundedRules]: Failed to close ticket ", ticket,
                     " Error: ", GetLastError());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Save funded account state to MT5 GlobalVariables                 |
//+------------------------------------------------------------------+
void SaveFundedState()
  {
   GlobalVariableSet(GV_PREFIX + "InitialBalance",   gInitialBalance);
   GlobalVariableSet(GV_PREFIX + "PeakEquity",       gPeakEquity);
   GlobalVariableSet(GV_PREFIX + "DailyStartEquity", gDailyStartEquity);
   GlobalVariableSet(GV_PREFIX + "DaysTraded",       (double)gDaysTraded);
   GlobalVariableSet(GV_PREFIX + "LastDayReset",     (double)gLastDayReset);
   GlobalVariableSet(GV_PREFIX + "MaxDDHit",         gMaxDDHit ? 1.0 : 0.0);
   GlobalVariableSet(GV_PREFIX + "TargetReached",    gTargetReached ? 1.0 : 0.0);
   GlobalVariableSet(GV_PREFIX + "DailyLimitHit",    gDailyLimitHit ? 1.0 : 0.0);
  }

//+------------------------------------------------------------------+
//| Load funded account state from MT5 GlobalVariables.             |
//| Called in OnInit(). Initialises state on first run.              |
//+------------------------------------------------------------------+
void LoadFundedState()
  {
   double storedBalance = 0.0;
   if(GlobalVariableGet(GV_PREFIX + "InitialBalance", storedBalance) && storedBalance > 0.0)
     {
      //--- Restore persisted state
      gInitialBalance   = storedBalance;
      GlobalVariableGet(GV_PREFIX + "PeakEquity",       gPeakEquity);
      GlobalVariableGet(GV_PREFIX + "DailyStartEquity", gDailyStartEquity);
      double daysD = 0.0;
      GlobalVariableGet(GV_PREFIX + "DaysTraded",       daysD);
      gDaysTraded = (int)daysD;
      double lastReset = 0.0;
      GlobalVariableGet(GV_PREFIX + "LastDayReset",     lastReset);
      gLastDayReset = (datetime)lastReset;
      double maxDDFlag = 0.0;
      GlobalVariableGet(GV_PREFIX + "MaxDDHit",         maxDDFlag);
      gMaxDDHit = (maxDDFlag > 0.5);
      double targetFlag = 0.0;
      GlobalVariableGet(GV_PREFIX + "TargetReached",    targetFlag);
      gTargetReached = (targetFlag > 0.5);
      double dailyFlag = 0.0;
      GlobalVariableGet(GV_PREFIX + "DailyLimitHit",    dailyFlag);
      gDailyLimitHit = (dailyFlag > 0.5);

      Print("PropPasserEA [FundedRules]: State restored — InitBal=", gInitialBalance,
            " PeakEq=", gPeakEquity, " DaysTraded=", gDaysTraded);
     }
   else
     {
      //--- First-time initialisation
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      gInitialBalance   = (InpInitialBalance > 0.0) ? InpInitialBalance
                           : AccountInfoDouble(ACCOUNT_BALANCE);
      gPeakEquity       = equity;
      gDailyStartEquity = equity;
      gDaysTraded       = 0;
      gLastDayReset     = TimeCurrent();
      gMaxDDHit         = false;
      gTargetReached    = false;
      gDailyLimitHit    = false;

      SaveFundedState();
      Print("PropPasserEA [FundedRules]: First run — InitBal=", gInitialBalance);
     }
  }

//+------------------------------------------------------------------+
//| Main funded rules check — called every tick.                     |
//| Handles: daily reset, peak tracking, DD checks, target check,   |
//|          consistency rule.                                       |
//+------------------------------------------------------------------+
void UpdateFundedRules()
  {
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);

   //--- 1. Daily reset: new calendar day?
   MqlDateTime now, last;
   TimeCurrent(now);
   TimeToStruct(gLastDayReset, last);

   if(now.day_of_year != last.day_of_year || now.year != last.year)
     {
      gDailyStartEquity = equity;
      gDailyLimitHit    = false;
      gLastDayReset     = TimeCurrent();
      gDaysTraded++;
      SaveFundedState();
      Print("PropPasserEA [FundedRules]: New day — DailyStartEquity=", gDailyStartEquity,
            " DaysTraded=", gDaysTraded);
     }

   //--- 2. Update all-time peak equity
   if(equity > gPeakEquity)
     {
      gPeakEquity = equity;
      SaveFundedState();
     }

   //--- 3. Permanent stop already hit — nothing more to do
   if(gMaxDDHit)
      return;

   //--- 4. Daily drawdown check
   if(gDailyStartEquity > 0.0)
     {
      double dailyDD = (gDailyStartEquity - equity) / gDailyStartEquity * 100.0;
      if(dailyDD >= InpMaxDailyDrawdown && !gDailyLimitHit)
        {
         gDailyLimitHit = true;
         SaveFundedState();
         CloseAllPositions(StringFormat("Daily DD %.2f%% >= limit %.2f%%",
                                        dailyDD, InpMaxDailyDrawdown));
         Print("PropPasserEA [FundedRules]: Daily drawdown limit reached: ", dailyDD, "%");
        }
     }

   //--- 5. Overall drawdown check (peak-to-trough and from initial balance)
   double overallDDFromPeak    = (gPeakEquity > 0.0)
                                  ? (gPeakEquity - equity) / gPeakEquity * 100.0 : 0.0;
   double overallDDFromInitial = (gInitialBalance > 0.0)
                                  ? (gInitialBalance - equity) / gInitialBalance * 100.0 : 0.0;

   if(overallDDFromPeak >= InpMaxOverallDrawdown || overallDDFromInitial >= InpMaxOverallDrawdown)
     {
      gMaxDDHit = true;
      SaveFundedState();
      CloseAllPositions(StringFormat("Overall DD %.2f%% (peak) / %.2f%% (initial) >= limit %.2f%%",
                                      overallDDFromPeak, overallDDFromInitial, InpMaxOverallDrawdown));
      Print("PropPasserEA [FundedRules]: Overall drawdown limit reached — EA permanently stopped");
     }

   //--- 6. Profit target check
   if(!gTargetReached && gInitialBalance > 0.0)
     {
      double profitPct = (balance - gInitialBalance) / gInitialBalance * 100.0;
      if(profitPct >= InpProfitTarget)
        {
         gTargetReached = true;
         SaveFundedState();
         Print("PropPasserEA [FundedRules]: *** CHALLENGE TARGET REACHED! Profit: ",
               DoubleToString(profitPct, 2), "% ***");
        }
     }

   //--- 7. Consistency rule (optional)
   if(InpEnableConsistency && !gDailyLimitHit)
     {
      double totalProfit = balance - gInitialBalance;
      double dailyProfit = balance - gDailyStartEquity;

      if(totalProfit > 0.0 && (dailyProfit / totalProfit * 100.0) > InpConsistencyLimit)
        {
         gDailyLimitHit = true;
         SaveFundedState();
         Print("PropPasserEA [FundedRules]: Consistency rule — today's profit (",
               DoubleToString(dailyProfit / totalProfit * 100.0, 1),
               "%) exceeded limit (", InpConsistencyLimit, "%). Stopping for today.");
        }
     }
  }

//+------------------------------------------------------------------+
//| Helper: current daily drawdown percentage                        |
//+------------------------------------------------------------------+
double GetDailyDDPct()
  {
   if(gDailyStartEquity <= 0.0) return 0.0;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   return (gDailyStartEquity - equity) / gDailyStartEquity * 100.0;
  }

//+------------------------------------------------------------------+
//| Helper: current overall drawdown from peak equity                |
//+------------------------------------------------------------------+
double GetOverallDDPct()
  {
   if(gPeakEquity <= 0.0) return 0.0;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   return (gPeakEquity - equity) / gPeakEquity * 100.0;
  }

//+------------------------------------------------------------------+
//| Helper: current profit progress toward target                    |
//+------------------------------------------------------------------+
double GetProfitProgressPct()
  {
   if(gInitialBalance <= 0.0) return 0.0;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   return (balance - gInitialBalance) / gInitialBalance * 100.0;
  }
//+------------------------------------------------------------------+
