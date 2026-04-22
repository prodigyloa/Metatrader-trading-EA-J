//+------------------------------------------------------------------+
//|                                      MAConvergenceSignal_jase.mq5 |
//|                              MA Convergence Signal Indicator      |
//+------------------------------------------------------------------+
#property copyright   "jase"
#property version     "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "BuySignal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2

#property indicator_label2  "SellSignal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

//--- enums
enum ENUM_SIGNAL_MODE
{
   MODE_ZERO_CROSS,   // Confirmed MA cross on closed bar
   MODE_PRE_CROSS,    // One bar before cross (gap at minimum)
   MODE_EXTREME,      // At histogram peak/trough contraction
};

//--- inputs
input int                InpFastPeriod  = 5;
input int                InpSlowPeriod  = 14;
input ENUM_MA_METHOD     InpMAMethod    = MODE_EMA;
input ENUM_APPLIED_PRICE InpPrice       = PRICE_CLOSE;
input ENUM_SIGNAL_MODE   InpSignalMode  = MODE_ZERO_CROSS;
input int                InpLookback    = 10;
input double             InpExtremeMult = 1.5;
input bool               InpShowDash    = true;
input ENUM_BASE_CORNER   InpCorner      = CORNER_RIGHT_UPPER;
input int                InpDashX       = 15;
input int                InpDashY       = 20;

//--- indicator buffers
double BullBuffer[];
double BearBuffer[];

//--- MA handles
int g_fastHandle = INVALID_HANDLE;
int g_slowHandle = INVALID_HANDLE;

//--- dashboard label names
string g_dashLabels[7];
int    g_lineSpacing = 18;

//+------------------------------------------------------------------+
//| Timeframe short name                                             |
//+------------------------------------------------------------------+
string TimeframeShortName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "??";
   }
}

//+------------------------------------------------------------------+
//| Create a single OBJ_LABEL                                        |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr)
{
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);

   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    InpCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  9);
   ObjectSetString(0,  name, OBJPROP_FONT,      "Courier New");
   ObjectSetString(0,  name, OBJPROP_TEXT,      text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    true);
}

//+------------------------------------------------------------------+
//| InitDashboard — create all label objects                         |
//+------------------------------------------------------------------+
void InitDashboard()
{
   if(!InpShowDash)
      return;

   g_dashLabels[0] = "MCS_Line0";
   g_dashLabels[1] = "MCS_Line1";
   g_dashLabels[2] = "MCS_Line2";
   g_dashLabels[3] = "MCS_Line3";
   g_dashLabels[4] = "MCS_Line4";
   g_dashLabels[5] = "MCS_Line5";
   g_dashLabels[6] = "MCS_Line6";

   string modeName;
   switch(InpSignalMode)
   {
      case MODE_ZERO_CROSS: modeName = "ZERO CROSS"; break;
      case MODE_PRE_CROSS:  modeName = "PRE";        break;
      case MODE_EXTREME:    modeName = "EXTREME";    break;
      default:              modeName = "???";        break;
   }

   int baseY = InpDashY;
   CreateLabel(g_dashLabels[0], InpDashX, baseY + 0 * g_lineSpacing, "== MA Convergence ==",                     clrGold);
   CreateLabel(g_dashLabels[1], InpDashX, baseY + 1 * g_lineSpacing, "Mode: " + modeName,                        clrSilver);
   CreateLabel(g_dashLabels[2], InpDashX, baseY + 2 * g_lineSpacing, "Fast MA(" + IntegerToString(InpFastPeriod) + "):  -.--", clrWhite);
   CreateLabel(g_dashLabels[3], InpDashX, baseY + 3 * g_lineSpacing, "Slow MA(" + IntegerToString(InpSlowPeriod) + "): -.--", clrWhite);
   CreateLabel(g_dashLabels[4], InpDashX, baseY + 4 * g_lineSpacing, "Gap:         -.--",                        clrSilver);
   CreateLabel(g_dashLabels[5], InpDashX, baseY + 5 * g_lineSpacing, "Signal: --",                               clrSilver);
   CreateLabel(g_dashLabels[6], InpDashX, baseY + 6 * g_lineSpacing, "TF: " + TimeframeShortName(PERIOD_CURRENT), clrSilver);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| UpdateDashboard                                                  |
//+------------------------------------------------------------------+
void UpdateDashboard(double fastVal, double slowVal, double gap,
                     bool isBuy, bool isSell)
{
   if(!InpShowDash)
      return;

   color gapColor    = (gap > 0) ? clrLime : clrRed;
   color signalColor;
   string signalText;
   if(isBuy)
   {
      signalColor = clrLime;
      signalText  = "Signal: BUY";
   }
   else if(isSell)
   {
      signalColor = clrRed;
      signalText  = "Signal: SELL";
   }
   else
   {
      signalColor = clrSilver;
      signalText  = "Signal: --";
   }

   ObjectSetString(0, g_dashLabels[2], OBJPROP_TEXT,
                   "Fast MA(" + IntegerToString(InpFastPeriod) + "):  " + DoubleToString(fastVal, 2));
   ObjectSetString(0, g_dashLabels[3], OBJPROP_TEXT,
                   "Slow MA(" + IntegerToString(InpSlowPeriod) + "): " + DoubleToString(slowVal, 2));

   ObjectSetString(0,  g_dashLabels[4], OBJPROP_TEXT,
                   "Gap:         " + DoubleToString(gap, 2));
   ObjectSetInteger(0, g_dashLabels[4], OBJPROP_COLOR, gapColor);

   ObjectSetString(0,  g_dashLabels[5], OBJPROP_TEXT,  signalText);
   ObjectSetInteger(0, g_dashLabels[5], OBJPROP_COLOR, signalColor);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| DestroyDashboard                                                 |
//+------------------------------------------------------------------+
void DestroyDashboard()
{
   for(int i = 0; i < 7; i++)
   {
      if(g_dashLabels[i] != "" && ObjectFind(0, g_dashLabels[i]) >= 0)
         ObjectDelete(0, g_dashLabels[i]);
   }
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- buffer 0: buy arrows
   SetIndexBuffer(0, BullBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE,  DRAW_ARROW);
   PlotIndexSetInteger(0, PLOT_ARROW,      241);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, clrLime);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 2);
   PlotIndexSetDouble(0,  PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- buffer 1: sell arrows
   SetIndexBuffer(1, BearBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE,  DRAW_ARROW);
   PlotIndexSetInteger(1, PLOT_ARROW,      242);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, clrRed);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, 2);
   PlotIndexSetDouble(1,  PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- MA handles
   g_fastHandle = iMA(NULL, PERIOD_CURRENT, InpFastPeriod, 0, InpMAMethod, InpPrice);
   g_slowHandle = iMA(NULL, PERIOD_CURRENT, InpSlowPeriod, 0, InpMAMethod, InpPrice);

   if(g_fastHandle == INVALID_HANDLE || g_slowHandle == INVALID_HANDLE)
   {
      Print("MAConvergenceSignal: failed to create MA handles");
      return INIT_FAILED;
   }

   InitDashboard();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_fastHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_fastHandle);
      g_fastHandle = INVALID_HANDLE;
   }
   if(g_slowHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_slowHandle);
      g_slowHandle = INVALID_HANDLE;
   }
   DestroyDashboard();
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   int minBars = InpSlowPeriod + InpLookback + 5;

   if(rates_total < minBars)
      return prev_calculated;

   //--- only process on new bar
   if(rates_total == prev_calculated)
      return prev_calculated;

   //--- number of bars to copy: we need at least InpLookback+25 to cover all modes
   int copyCount = InpLookback + 25;
   if(copyCount > rates_total)
      copyCount = rates_total;

   double fastMA[];
   double slowMA[];
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);

   if(CopyBuffer(g_fastHandle, 0, 0, copyCount, fastMA) <= 0)
      return prev_calculated;
   if(CopyBuffer(g_slowHandle, 0, 0, copyCount, slowMA) <= 0)
      return prev_calculated;

   //--- build gap array (AsSeries=true so index 0 = current bar)
   int gapSize = copyCount;
   double gap[];
   ArrayResize(gap, gapSize);
   for(int i = 0; i < gapSize; i++)
      gap[i] = fastMA[i] - slowMA[i];

   //--- evaluate signal on bar index 1 (last closed bar)
   bool isBuy  = false;
   bool isSell = false;

   switch(InpSignalMode)
   {
      case MODE_ZERO_CROSS:
         if(gapSize >= 3)
         {
            if(gap[2] < 0.0 && gap[1] > 0.0) isBuy  = true;
            if(gap[2] > 0.0 && gap[1] < 0.0) isSell = true;
         }
         break;

      case MODE_PRE_CROSS:
         if(gapSize >= 4)
         {
            if(gap[1] < 0.0 &&
               MathAbs(gap[1]) < MathAbs(gap[2]) &&
               MathAbs(gap[1]) < MathAbs(gap[3]))
               isBuy = true;

            if(gap[1] > 0.0 &&
               MathAbs(gap[1]) < MathAbs(gap[2]) &&
               MathAbs(gap[1]) < MathAbs(gap[3]))
               isSell = true;
         }
         break;

      case MODE_EXTREME:
      {
         if(gapSize >= InpLookback + 22)
         {
            //--- average of abs(gap[1..20])
            double sumGap = 0.0;
            for(int k = 1; k <= 20; k++)
               sumGap += MathAbs(gap[k]);
            double avgGap = sumGap / 20.0;

            //--- min and max of gap[2..InpLookback+2]
            int endIdx = InpLookback + 2;
            double minVal = gap[2];
            double maxVal = gap[2];
            for(int k = 3; k <= endIdx; k++)
            {
               if(gap[k] < minVal) minVal = gap[k];
               if(gap[k] > maxVal) maxVal = gap[k];
            }

            //--- BUY: gap[2] is the minimum AND gap[1] > gap[2] AND |gap[2]| >= mult*avg
            if(gap[2] == minVal && gap[1] > gap[2] &&
               MathAbs(gap[2]) >= InpExtremeMult * avgGap)
               isBuy = true;

            //--- SELL: gap[2] is the maximum AND gap[1] < gap[2] AND |gap[2]| >= mult*avg
            if(gap[2] == maxVal && gap[1] < gap[2] &&
               MathAbs(gap[2]) >= InpExtremeMult * avgGap)
               isSell = true;
         }
         break;
      }
   }

   //--- place arrows only on bar 1 (last closed bar), clear current bar
   BullBuffer[0] = EMPTY_VALUE;
   BearBuffer[0] = EMPTY_VALUE;

   if(isBuy)
   {
      BullBuffer[1] = iLow(NULL, PERIOD_CURRENT, 1) - 10.0 * _Point;
      BearBuffer[1] = EMPTY_VALUE;
   }
   else if(isSell)
   {
      BearBuffer[1] = iHigh(NULL, PERIOD_CURRENT, 1) + 10.0 * _Point;
      BullBuffer[1] = EMPTY_VALUE;
   }
   else
   {
      BullBuffer[1] = EMPTY_VALUE;
      BearBuffer[1] = EMPTY_VALUE;
   }

   //--- update dashboard
   UpdateDashboard(fastMA[1], slowMA[1], gap[1], isBuy, isSell);

   return rates_total;
}
//+------------------------------------------------------------------+
