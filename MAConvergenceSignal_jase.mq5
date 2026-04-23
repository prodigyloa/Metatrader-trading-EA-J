//+------------------------------------------------------------------+
//|                                      MAConvergenceSignal_jase.mq5 |
//|                              MA Convergence Signal Indicator      |
//+------------------------------------------------------------------+
#property copyright   "jase"
#property version     "1.01"
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
input int                InpFastPeriod  = 5;            // Fast MA Period
input int                InpSlowPeriod  = 14;           // Slow MA Period
input ENUM_MA_METHOD     InpMAMethod    = MODE_EMA;     // MA Method
input ENUM_APPLIED_PRICE InpPrice       = PRICE_CLOSE;  // Applied Price
input ENUM_SIGNAL_MODE   InpSignalMode  = MODE_PRE_CROSS; // Signal Mode
input int                InpLookback    = 10;           // Lookback for Extreme mode
input double             InpExtremeMult = 1.5;          // Extreme multiplier
input bool               InpShowDash    = true;         // Show dashboard
input ENUM_BASE_CORNER   InpCorner      = CORNER_LEFT_UPPER; // Dashboard corner
input int                InpDashX       = 200;          // Dashboard X offset
input int                InpDashY       = 30;           // Dashboard Y offset

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
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,    false);
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
      case MODE_PRE_CROSS:  modeName = "PRE-CROSS";  break;
      case MODE_EXTREME:    modeName = "EXTREME";    break;
      default:              modeName = "???";        break;
   }

   int baseY = InpDashY;
   CreateLabel(g_dashLabels[0], InpDashX, baseY + 0 * g_lineSpacing, "== MA Convergence ==",                      clrGold);
   CreateLabel(g_dashLabels[1], InpDashX, baseY + 1 * g_lineSpacing, "Mode: " + modeName,                         clrSilver);
   CreateLabel(g_dashLabels[2], InpDashX, baseY + 2 * g_lineSpacing, "Fast MA(" + IntegerToString(InpFastPeriod) + "):  -.--", clrWhite);
   CreateLabel(g_dashLabels[3], InpDashX, baseY + 3 * g_lineSpacing, "Slow MA(" + IntegerToString(InpSlowPeriod) + "): -.--", clrWhite);
   CreateLabel(g_dashLabels[4], InpDashX, baseY + 4 * g_lineSpacing, "Gap:         -.--",                         clrSilver);
   CreateLabel(g_dashLabels[5], InpDashX, baseY + 5 * g_lineSpacing, "Signal: --",                                clrSilver);
   CreateLabel(g_dashLabels[6], InpDashX, baseY + 6 * g_lineSpacing, "TF: " + TimeframeShortName(PERIOD_CURRENT),  clrSilver);

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

   color  gapColor = (gap > 0) ? clrLime : clrRed;
   color  signalColor;
   string signalText;

   if(isBuy)        { signalColor = clrLime;   signalText = "Signal: BUY";  }
   else if(isSell)  { signalColor = clrRed;    signalText = "Signal: SELL"; }
   else             { signalColor = clrSilver; signalText = "Signal: --";   }

   ObjectSetString(0, g_dashLabels[2], OBJPROP_TEXT,
                   "Fast MA(" + IntegerToString(InpFastPeriod) + "):  " + DoubleToString(fastVal, 2));
   ObjectSetString(0, g_dashLabels[3], OBJPROP_TEXT,
                   "Slow MA(" + IntegerToString(InpSlowPeriod) + "): " + DoubleToString(slowVal, 2));

   ObjectSetString(0,  g_dashLabels[4], OBJPROP_TEXT,  "Gap:         " + DoubleToString(gap, 2));
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
//| Evaluate one bar and write arrow to buffer if signal fires       |
//|                                                                  |
//| i          — evaluation point in forward indexing               |
//|              (0=oldest, rates_total-1=current forming bar)       |
//| gap[]      — forward-indexed gap array (fastMA - slowMA)         |
//| rates_total— total bars in the indicator context                 |
//|                                                                  |
//| Signal placement:                                                |
//|   MODE_ZERO_CROSS : arrow at buffer[i]   (the cross bar)         |
//|   MODE_PRE_CROSS  : arrow at buffer[i-1] (the minimum bar)       |
//|   MODE_EXTREME    : arrow at buffer[i-1] (the extreme bar)       |
//|                                                                  |
//| No repainting: all bars evaluated are fully closed.              |
//+------------------------------------------------------------------+
void EvaluateAndWrite(const int i, const double &gap[], const int rates_total)
{
   bool isBuy    = false;
   bool isSell   = false;
   int  arrowBar = -1;

   switch(InpSignalMode)
   {
      //--- Arrow fires on the bar where gap crosses zero.
      //    gap[i-1] and gap[i] have opposite signs → arrow at i.
      case MODE_ZERO_CROSS:
         if(i >= 1)
         {
            if(gap[i-1] <= 0.0 && gap[i] > 0.0) { isBuy  = true; arrowBar = i; }
            if(gap[i-1] >= 0.0 && gap[i] < 0.0) { isSell = true; arrowBar = i; }
         }
         break;

      //--- Arrow fires ONCE per convergence event, placed at the minimum-gap bar.
      //    At evaluation point i, bar i-1 is confirmed as the local minimum when:
      //      |gap[i-1]| < |gap[i-2]|  (was converging into i-1)
      //      |gap[i-1]| < |gap[i]|    (now diverging away from i-1)
      //    Direction determined by sign of gap at that minimum.
      case MODE_PRE_CROSS:
         if(i >= 2)
         {
            double absMin = MathAbs(gap[i-1]);
            if(absMin < MathAbs(gap[i-2]) && absMin < MathAbs(gap[i]))
            {
               if(gap[i-1] < 0.0)      { isBuy  = true; arrowBar = i - 1; }
               else if(gap[i-1] > 0.0) { isSell = true; arrowBar = i - 1; }
            }
         }
         break;

      //--- Arrow fires when the gap makes an extreme contraction relative to
      //    recent average, and bar i-1 is the extreme value that bar i has left.
      case MODE_EXTREME:
      {
         if(i < InpLookback + 21) break;

         //--- average |gap| over the 20 bars ending at i (bars i-19 .. i)
         double sumGap = 0.0;
         for(int k = 0; k < 20; k++)
            sumGap += MathAbs(gap[i - k]);
         double avgGap = sumGap / 20.0;

         //--- min and max of gap over [i-1-InpLookback .. i-1]
         int lo = i - 1 - InpLookback;
         if(lo < 0) break;

         double minVal = gap[i-1];
         double maxVal = gap[i-1];
         for(int k = lo; k <= i - 1; k++)
         {
            if(gap[k] < minVal) minVal = gap[k];
            if(gap[k] > maxVal) maxVal = gap[k];
         }

         if(gap[i-1] == minVal && gap[i] > gap[i-1] &&
            MathAbs(gap[i-1]) >= InpExtremeMult * avgGap)
         {
            isBuy  = true;
            arrowBar = i - 1;
         }
         else if(gap[i-1] == maxVal && gap[i] < gap[i-1] &&
                 MathAbs(gap[i-1]) >= InpExtremeMult * avgGap)
         {
            isSell   = true;
            arrowBar = i - 1;
         }
         break;
      }
   }

   if((!isBuy && !isSell) || arrowBar < 0 || arrowBar >= rates_total)
      return;

   //--- convert forward index to bar shift for iLow/iHigh
   int shift = rates_total - 1 - arrowBar;

   if(isBuy)
   {
      BullBuffer[arrowBar] = iLow(_Symbol, PERIOD_CURRENT, shift) - 10.0 * _Point;
      BearBuffer[arrowBar] = EMPTY_VALUE;
   }
   else
   {
      BearBuffer[arrowBar] = iHigh(_Symbol, PERIOD_CURRENT, shift) + 10.0 * _Point;
      BullBuffer[arrowBar] = EMPTY_VALUE;
   }
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- buffer 0: buy arrows
   SetIndexBuffer(0, BullBuffer, INDICATOR_DATA);
   ArraySetAsSeries(BullBuffer, false);
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE,   DRAW_ARROW);
   PlotIndexSetInteger(0, PLOT_ARROW,       241);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR,  clrLime);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH,  2);
   PlotIndexSetDouble(0,  PLOT_EMPTY_VALUE, EMPTY_VALUE);

   //--- buffer 1: sell arrows
   SetIndexBuffer(1, BearBuffer, INDICATOR_DATA);
   ArraySetAsSeries(BearBuffer, false);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE,   DRAW_ARROW);
   PlotIndexSetInteger(1, PLOT_ARROW,       242);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR,  clrRed);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH,  2);
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
   if(g_fastHandle != INVALID_HANDLE) { IndicatorRelease(g_fastHandle); g_fastHandle = INVALID_HANDLE; }
   if(g_slowHandle != INVALID_HANDLE) { IndicatorRelease(g_slowHandle); g_slowHandle = INVALID_HANDLE; }
   DestroyDashboard();
}

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//| Forward indexing throughout: index 0 = oldest, RT-1 = current.  |
//| Last closed bar = rates_total-2 = the signal evaluation point.   |
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
   int minBars = InpSlowPeriod + InpLookback + 22;

   if(rates_total < minBars)
      return prev_calculated;

   //--- skip intra-bar recalculations
   if(rates_total == prev_calculated)
      return prev_calculated;

   //--- copy all bars into forward-indexed arrays (0=oldest, RT-1=current)
   double fastMA[], slowMA[];
   ArraySetAsSeries(fastMA, false);
   ArraySetAsSeries(slowMA, false);

   if(CopyBuffer(g_fastHandle, 0, 0, rates_total, fastMA) <= 0)
      return prev_calculated;
   if(CopyBuffer(g_slowHandle, 0, 0, rates_total, slowMA) <= 0)
      return prev_calculated;

   //--- build gap array
   double gap[];
   ArrayResize(gap, rates_total);
   for(int j = 0; j < rates_total; j++)
      gap[j] = fastMA[j] - slowMA[j];

   if(prev_calculated == 0)
   {
      //--- first load: populate full history
      ArrayInitialize(BullBuffer, EMPTY_VALUE);
      ArrayInitialize(BearBuffer, EMPTY_VALUE);

      for(int i = minBars; i <= rates_total - 2; i++)
         EvaluateAndWrite(i, gap, rates_total);
   }
   else
   {
      //--- subsequent calls: only evaluate the last closed bar
      int i = rates_total - 2;
      if(i >= minBars)
         EvaluateAndWrite(i, gap, rates_total);
   }

   //--- update dashboard with last-closed-bar values
   int lc = rates_total - 2;
   if(lc >= 0)
      UpdateDashboard(fastMA[lc], slowMA[lc], gap[lc],
                      BullBuffer[lc] != EMPTY_VALUE,
                      BearBuffer[lc] != EMPTY_VALUE);

   return rates_total;
}
//+------------------------------------------------------------------+
