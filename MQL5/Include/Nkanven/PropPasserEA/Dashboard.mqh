//+------------------------------------------------------------------+
//|                                                  Dashboard.mqh   |
//|                        Copyright 2024, Nkondog Anselme Venceslas |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Renders a live status panel on the chart using OBJ_LABEL objects.|
//| Shows funded account rule progress: daily DD, overall DD, profit,|
//| status, days traded, strategy, and account balance/equity.       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nkondog Anselme Venceslas"
#property link      "https://www.mql5.com"

#define DASH_PREFIX  "PPE_Dash_"
#define DASH_LINES   9
#define DASH_LINE_H  18   // pixels between lines

//+------------------------------------------------------------------+
//| Internal helpers                                                 |
//+------------------------------------------------------------------+
string DashName(int line)
  {
   return DASH_PREFIX + IntegerToString(line);
  }

void SetLabel(string name, string text, color clr)
  {
   ObjectSetString(0,  name, OBJPROP_TEXT,  text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

color GetDDColor(double current, double limit)
  {
   if(limit <= 0) return clrSilver;
   double ratio = current / limit;
   if(ratio >= 0.90) return clrRed;
   if(ratio >= 0.70) return clrOrange;
   return clrLime;
  }

color GetStatusColor()
  {
   if(gMaxDDHit)      return clrRed;
   if(gTargetReached) return clrGold;
   if(gDailyLimitHit) return clrOrange;
   return clrLime;
  }

string GetStatusText()
  {
   if(gMaxDDHit)      return "HALTED — Max DD Hit";
   if(gTargetReached) return "TARGET REACHED!";
   if(gDailyLimitHit) return "Daily Limit — Resume Tomorrow";
   return "ACTIVE";
  }

string PeriodShortName(ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return "?";
     }
  }

string StrategyShortName()
  {
   return (InpStrategy == STRATEGY_EMA_PINBAR) ? "EMA+PinBar" : "EMA+Crossover";
  }

//+------------------------------------------------------------------+
//| Create all dashboard label objects                               |
//+------------------------------------------------------------------+
void InitDashboard()
  {
   if(!InpShowDashboard) return;

   for(int i = 0; i < DASH_LINES; i++)
     {
      string name = DashName(i);
      //--- Remove any stale object from a previous EA load
      if(ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);

      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,    InpDashboardCorner);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpDashboardX);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpDashboardY + i * DASH_LINE_H);
      ObjectSetString(0,  name, OBJPROP_FONT,      "Courier New");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  9);
      ObjectSetInteger(0, name, OBJPROP_COLOR,     clrSilver);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetString(0,  name, OBJPROP_TEXT,       "...");
     }
   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Refresh all dashboard labels with current account/EA state       |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(!InpShowDashboard) return;

   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyDD    = GetDailyDDPct();
   double overallDD  = GetOverallDDPct();
   double profitPct  = GetProfitProgressPct();

   string tf         = PeriodShortName(InpTimeFrame == PERIOD_CURRENT
                                        ? (ENUM_TIMEFRAMES)Period() : InpTimeFrame);

   //--- Line 0: Title bar
   SetLabel(DashName(0),
            "=== PropPasserEA | " + gSymbol + " " + tf + " ===",
            clrGold);

   //--- Line 1: Balance / Equity
   SetLabel(DashName(1),
            StringFormat("Bal: %.2f   Eq: %.2f", balance, equity),
            clrWhite);

   //--- Line 2: Daily drawdown
   SetLabel(DashName(2),
            StringFormat("Daily DD:   %+.2f%% / %.1f%%", dailyDD, InpMaxDailyDrawdown),
            GetDDColor(dailyDD, InpMaxDailyDrawdown));

   //--- Line 3: Overall drawdown
   SetLabel(DashName(3),
            StringFormat("Overall DD: %+.2f%% / %.1f%%", overallDD, InpMaxOverallDrawdown),
            GetDDColor(overallDD, InpMaxOverallDrawdown));

   //--- Line 4: Profit progress toward target
   color profitColor = (profitPct >= InpProfitTarget) ? clrGold
                        : (profitPct > 0) ? clrDeepSkyBlue : clrSilver;
   SetLabel(DashName(4),
            StringFormat("Profit:     %+.2f%% / %.1f%%", profitPct, InpProfitTarget),
            profitColor);

   //--- Line 5: EA status
   SetLabel(DashName(5),
            "Status: " + GetStatusText(),
            GetStatusColor());

   //--- Line 6: Days traded
   SetLabel(DashName(6),
            StringFormat("Days Traded: %d", gDaysTraded),
            clrSilver);

   //--- Line 7: Open positions
   SetLabel(DashName(7),
            StringFormat("Positions:   %d buy  %d sell", gTotalBuyPositions, gTotalSellPositions),
            clrSilver);

   //--- Line 8: Strategy info
   SetLabel(DashName(8),
            "Strategy: " + StrategyShortName() + "  Risk: " +
            DoubleToString(InpMaxRiskPerTrade, 1) + "%/trade",
            clrSilver);

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Remove all dashboard objects from the chart                      |
//+------------------------------------------------------------------+
void DestroyDashboard()
  {
   for(int i = 0; i < DASH_LINES; i++)
     {
      string name = DashName(i);
      if(ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);
     }
   ChartRedraw(0);
  }
//+------------------------------------------------------------------+
