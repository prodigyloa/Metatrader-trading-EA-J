//+------------------------------------------------------------------+
//|  MAConvergenceSignal.mq5                                         |
//|  Copyright 2024, Production-Ready MQL5 Indicator                 |
//|  Detects MA gap histogram extremes and contraction signals        |
//+------------------------------------------------------------------+
#property copyright "2024"
#property link      ""
#property version   "1.00"
#property description "Fires arrows when the MA5-MA14 gap peaks then contracts back"

// Indicator lives in its own subwindow so the histogram and arrows
// share the same scale (gap units). Arrows at bar[1] are positioned
// just beyond the histogram bar using a proportional gap offset.
#property indicator_separate_window
#property indicator_buffers 4
#property indicator_plots   3

// Plot 0: Bull arrows (up arrow at gap level, subwindow)
#property indicator_label1  "Bull Signal"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

// Plot 1: Bear arrows (down arrow at gap level, subwindow)
#property indicator_label2  "Bear Signal"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

// Plot 2: Color histogram of the MA gap
#property indicator_label3  "MA Gap"
#property indicator_type3   DRAW_COLOR_HISTOGRAM
#property indicator_color3  clrSteelBlue,clrTomato
#property indicator_style3  STYLE_SOLID
#property indicator_width3  2

//--- Inputs
input int              InpFastPeriod        = 5;                   // Fast MA Period
input int              InpSlowPeriod        = 14;                  // Slow MA Period
input ENUM_MA_METHOD   InpMAMethod          = MODE_EMA;            // MA Method
input int              InpLookback          = 10;                  // Bars to look back for extreme
input double           InpExtremeMultiplier = 1.5;                 // Extreme threshold multiplier
input bool             InpShowDashboard     = true;                // Show dashboard panel
input ENUM_BASE_CORNER InpCorner            = CORNER_RIGHT_UPPER;  // Dashboard corner
input int              InpDashX             = 15;                  // Dashboard X offset
input int              InpDashY             = 20;                  // Dashboard Y offset

//--- Indicator buffers (globally declared, bound in OnInit)
double BullBuffer[];      // Plot 0 — bull arrow positions (gap scale)
double BearBuffer[];      // Plot 1 — bear arrow positions (gap scale)
double GapBuffer[];       // Plot 2 data — MA5 minus MA14
double GapColorBuffer[];  // Plot 2 color index: 0=steelblue, 1=tomato

//--- MA handles, created once in OnInit and released in OnDeinit
int hFastMA = INVALID_HANDLE;
int hSlowMA = INVALID_HANDLE;

//--- Dashboard constants
#define DASH_PREFIX  "MCS_Dash_"
#define DASH_LINES   7

//+------------------------------------------------------------------+
//| Dashboard helpers                                                  |
//+------------------------------------------------------------------+

void DashboardDestroy()
  {
   for(int i = 0; i < DASH_LINES; i++)
     {
      string name = DASH_PREFIX + IntegerToString(i);
      if(ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);
     }
   ChartRedraw(0);
  }

void DashboardCreateLine(int idx, color clr)
  {
   string name = DASH_PREFIX + IntegerToString(idx);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     InpCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  InpDashX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  InpDashY + idx * 18);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   9);
   ObjectSetString (0, name, OBJPROP_FONT,       "Courier New");
   ObjectSetString (0, name, OBJPROP_TEXT,       "");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
  }

void DashboardCreate()
  {
   DashboardDestroy();
   if(!InpShowDashboard) return;
   DashboardCreateLine(0, clrGold);    // title
   DashboardCreateLine(1, clrWhite);   // fast MA value
   DashboardCreateLine(2, clrWhite);   // slow MA value
   DashboardCreateLine(3, clrWhite);   // gap (color overridden per tick)
   DashboardCreateLine(4, clrSilver);  // gap extreme
   DashboardCreateLine(5, clrSilver);  // last signal (color overridden per tick)
   DashboardCreateLine(6, clrSilver);  // timeframe
  }

void DashboardUpdate(double fastVal, double slowVal, double curGap,
                     double extremeGap, int lastSig)
  {
   if(!InpShowDashboard) return;

   ObjectSetString(0, DASH_PREFIX "0", OBJPROP_TEXT,
                   "=== MA Convergence Signal ===");

   ObjectSetString(0, DASH_PREFIX "1", OBJPROP_TEXT,
                   StringFormat("Fast MA(%d):  %.2f", InpFastPeriod, fastVal));

   ObjectSetString(0, DASH_PREFIX "2", OBJPROP_TEXT,
                   StringFormat("Slow MA(%d):  %.2f", InpSlowPeriod, slowVal));

   ObjectSetString(0, DASH_PREFIX "3", OBJPROP_TEXT,
                   StringFormat("Gap:         %.2f", curGap));
   ObjectSetInteger(0, DASH_PREFIX "3", OBJPROP_COLOR,
                    curGap >= 0.0 ? clrLimeGreen : clrTomato);

   ObjectSetString(0, DASH_PREFIX "4", OBJPROP_TEXT,
                   StringFormat("Gap Extreme: %.2f", extremeGap));

   string sigText;  color sigColor;
   if(lastSig == 1)       { sigText = "BUY";  sigColor = clrLime;   }
   else if(lastSig == -1) { sigText = "SELL"; sigColor = clrTomato; }
   else                   { sigText = "--";   sigColor = clrSilver; }
   ObjectSetString (0, DASH_PREFIX "5", OBJPROP_TEXT,  "Last Signal: " + sigText);
   ObjectSetInteger(0, DASH_PREFIX "5", OBJPROP_COLOR, sigColor);

   ObjectSetString(0, DASH_PREFIX "6", OBJPROP_TEXT,
                   "Timeframe:   " + TimeframeToString(_Period));

   ChartRedraw(0);
  }

string TimeframeToString(ENUM_TIMEFRAMES tf)
  {
   switch(tf)
     {
      case PERIOD_M1:  return "M1";   case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";   case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";   case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";  case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";  case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";  case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";   case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";   case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";   case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";   case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";  default:         return "?";
     }
  }

//+------------------------------------------------------------------+
//| Evaluate signal at a given series position i (acts as "bar[1]")  |
//| fast[] and slow[] are AsSeries arrays; len = their valid length.  |
//| Returns +1 (bull), -1 (bear), or 0 (none).                       |
//| outGap2 receives the gap at position i+1 (the extreme candidate). |
//| outAvg  receives the 20-bar average absolute gap.                 |
//+------------------------------------------------------------------+
int EvalSignal(const double &fast[], const double &slow[],
               int i, int len,
               double barClose, double barOpen,
               double &outGap2, double &outAvg)
  {
   outGap2 = 0.0;
   outAvg  = 0.0;

   // Bounds check: need i+1+InpLookback-1 and i+2+19 = i+21
   int needed = i + MathMax(1 + InpLookback, 22);
   if(needed >= len) return 0;

   double gap1 = fast[i]   - slow[i];
   double gap2 = fast[i+1] - slow[i+1];
   outGap2 = gap2;

   // 20-bar rolling average absolute gap (bars i+2 .. i+21)
   double sumAbs = 0.0;
   for(int k = i + 2; k <= i + 21; k++)
      sumAbs += MathAbs(fast[k] - slow[k]);
   double avg = sumAbs / 20.0;
   outAvg = avg;
   double thresh = InpExtremeMultiplier * avg;

   // Find min and max over InpLookback bars starting at i+1
   double minG =  DBL_MAX, maxG = -DBL_MAX;
   int    minAt = i + 1,   maxAt = i + 1;
   for(int k = i + 1; k < i + 1 + InpLookback; k++)
     {
      double g = fast[k] - slow[k];
      if(g < minG) { minG = g; minAt = k; }
      if(g > maxG) { maxG = g; maxAt = k; }
     }

   // Bull conditions (mirrored bear below)
   if(gap1 < 0.0 && gap1 > gap2 && minAt == i + 1
      && MathAbs(gap2) >= thresh && barClose > barOpen)
      return 1;

   if(gap1 > 0.0 && gap1 < gap2 && maxAt == i + 1
      && MathAbs(gap2) >= thresh && barClose < barOpen)
      return -1;

   return 0;
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Create MA handles once; all subsequent CopyBuffer calls use these
   hFastMA = iMA(_Symbol, _Period, InpFastPeriod, 0, InpMAMethod, PRICE_CLOSE);
   hSlowMA = iMA(_Symbol, _Period, InpSlowPeriod, 0, InpMAMethod, PRICE_CLOSE);

   if(hFastMA == INVALID_HANDLE || hSlowMA == INVALID_HANDLE)
     {
      Print("MAConvergenceSignal: iMA handle creation failed");
      return INIT_FAILED;
     }

   // Bind buffers to plots
   SetIndexBuffer(0, BullBuffer,     INDICATOR_DATA);
   SetIndexBuffer(1, BearBuffer,     INDICATOR_DATA);
   SetIndexBuffer(2, GapBuffer,      INDICATOR_DATA);
   SetIndexBuffer(3, GapColorBuffer, INDICATOR_COLOR_INDEX);

   // Arrow symbol codes
   PlotIndexSetInteger(0, PLOT_ARROW,      241); // Wingdings up arrow
   PlotIndexSetInteger(1, PLOT_ARROW,      242); // Wingdings down arrow
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 2);
   PlotIndexSetInteger(1, PLOT_LINE_WIDTH, 2);

   // EMPTY_VALUE sentinel so gaps in arrows don't draw stale values
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   // Horizontal zero-line in the subwindow
   IndicatorSetInteger(INDICATOR_LEVELS,     1);
   IndicatorSetDouble (INDICATOR_LEVELVALUE, 0, 0.0);
   IndicatorSetInteger(INDICATOR_LEVELCOLOR, 0, clrGray);
   IndicatorSetInteger(INDICATOR_LEVELSTYLE, 0, STYLE_DASH);
   IndicatorSetInteger(INDICATOR_LEVELWIDTH, 0, 1);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      "MAConv(" + IntegerToString(InpFastPeriod) + ","
                                + IntegerToString(InpSlowPeriod) + ")");

   DashboardCreate();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hFastMA != INVALID_HANDLE) IndicatorRelease(hFastMA);
   if(hSlowMA != INVALID_HANDLE) IndicatorRelease(hSlowMA);
   DashboardDestroy();
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
   // Minimum bar requirement: slow period + lookback window + 20-bar avg + 3 guards
   int minBars = InpSlowPeriod + InpLookback + 23;
   if(rates_total < minBars)
      return prev_calculated;

   // --- Determine how many bars need (re-)processing ---
   // On the very first call fill all bars; otherwise only the newly closed bars.
   // +2 guard so bar[1] signal logic always has i+InpLookback+22 available.
   int limit;
   if(prev_calculated == 0)
      limit = rates_total - InpSlowPeriod - 1;
   else
      limit = rates_total - prev_calculated + 1;

   // CopyBuffer count: enough for histogram fill AND signal lookback/average
   int copyCount = limit + InpLookback + 25;
   if(copyCount > rates_total) copyCount = rates_total;

   // --- Fetch MA data (AsSeries: index 0 = newest bar) ---
   double fastMA[], slowMA[];
   ArraySetAsSeries(fastMA, true);
   ArraySetAsSeries(slowMA, true);

   if(CopyBuffer(hFastMA, 0, 0, copyCount, fastMA) < copyCount) return prev_calculated;
   if(CopyBuffer(hSlowMA, 0, 0, copyCount, slowMA) < copyCount) return prev_calculated;

   // --- Fill histogram and detect signals for all unprocessed bars ---
   // Series index i maps to chronological index (rates_total - 1 - i).
   // We iterate from oldest-unprocessed (limit) down to 0 (newest).

   // Track the last signal seen during this pass for dashboard display
   int    lastSig      = 0;
   double dashGap2     = 0.0;
   double dashFast     = fastMA[0];
   double dashSlow     = slowMA[0];

   for(int i = limit; i >= 0; i--)
     {
      int c = rates_total - 1 - i; // chronological index in price arrays

      // --- Histogram ---
      double gap    = fastMA[i] - slowMA[i];
      GapBuffer[c]      = gap;
      GapColorBuffer[c] = (gap >= 0.0) ? 0.0 : 1.0; // 0=steelblue, 1=tomato

      // --- Arrow buffers default to empty ---
      BullBuffer[c] = EMPTY_VALUE;
      BearBuffer[c] = EMPTY_VALUE;

      // Signal detection only on bar[1] and older closed bars (i >= 1)
      // Also skip bars where we don't have enough data for the full lookback
      if(i < 1) continue;

      double g2 = 0.0, avg = 0.0;
      int sig = EvalSignal(fastMA, slowMA, i, copyCount,
                           close[c], open[c], g2, avg);

      if(sig == 1)
        {
         // Up arrow just below the histogram bar; offset proportional to avg gap
         BullBuffer[c] = gap - avg * 0.3;
         lastSig  = 1;
         dashGap2 = g2;
        }
      else if(sig == -1)
        {
         // Down arrow just above the histogram bar
         BearBuffer[c] = gap + avg * 0.3;
         lastSig  = -1;
         dashGap2 = g2;
        }
     }

   // --- Dashboard update once per new bar (not every tick on same bar) ---
   if(prev_calculated != rates_total && InpShowDashboard)
     {
      double curGap = dashFast - dashSlow;
      DashboardUpdate(dashFast, dashSlow, curGap, dashGap2, lastSig);
     }

   return rates_total;
  }
//+------------------------------------------------------------------+
