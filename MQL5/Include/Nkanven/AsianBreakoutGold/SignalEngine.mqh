//+------------------------------------------------------------------+
//|                                               SignalEngine.mqh   |
//|                        Copyright 2024, Nkondog Anselme Venceslas |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Asian Range Breakout signal engine for XAUUSD M15.               |
//|                                                                   |
//| Flow:                                                             |
//|   1. UpdateAsianRange() — tracks high/low during Asian session,  |
//|      marks gAsianRangeReady when session closes.                 |
//|   2. CheckAsianBreakoutSignal() — fires during London open when  |
//|      a closed M15 bar breaks outside the range, filtered by H1   |
//|      200 EMA trend direction.                                    |
//|   3. GetSignal() — combines both; called from OnTick().          |
//|                                                                   |
//| g_h_ema_h1 must be assigned in OnInit() before the first tick.  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nkondog Anselme Venceslas"
#property link      "https://www.mql5.com"

//--- H1 200 EMA handle — set by AsianBreakoutGold.mq5 OnInit()
int g_h_ema_h1 = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Read a single double from an indicator buffer (safe)             |
//+------------------------------------------------------------------+
double GetIndValue(int handle, int buffer, int shift)
  {
   double arr[];
   ArraySetAsSeries(arr, true);
   if(CopyBuffer(handle, buffer, shift, 1, arr) < 1)
      return EMPTY_VALUE;
   return arr[0];
  }

//+------------------------------------------------------------------+
//| Returns true if 'hour' falls inside the Asian session window.    |
//| Handles overnight sessions (start > end, e.g. 23 -> 06).        |
//+------------------------------------------------------------------+
bool IsInAsianSession(int hour)
  {
   if(InpAsianSessionStart > InpAsianSessionEnd)
      return (hour >= InpAsianSessionStart || hour < InpAsianSessionEnd);
   return (hour >= InpAsianSessionStart && hour < InpAsianSessionEnd);
  }

//+------------------------------------------------------------------+
//| Update gAsianHigh / gAsianLow from closed M15 bars.              |
//|                                                                   |
//| Called every tick from OnTick().  Returns immediately when       |
//| outside the Asian session window (performance guard).            |
//|                                                                   |
//| Reset fires once per day when server hour reaches                |
//| InpAsianSessionStart and at least 20 h have elapsed since the    |
//| previous reset — this prevents double-fire within the same hour. |
//+------------------------------------------------------------------+
void UpdateAsianRange()
  {
   MqlDateTime t;
   TimeCurrent(t);
   int hour = t.hour;

   //--- Daily reset: fire when the Asian session starts for a new day
   if(hour == InpAsianSessionStart && TimeCurrent() - gLastAsianReset > 20 * 3600)
     {
      gAsianHigh       = 0.0;
      gAsianLow        = 999999.0;
      gAsianRangeReady = false;
      gTradedToday     = false;
      gLastAsianReset  = TimeCurrent();
     }

   //--- Outside Asian session: mark range ready at session close, then return
   if(!IsInAsianSession(hour))
     {
      if(hour == InpAsianSessionEnd && !gAsianRangeReady && gAsianHigh > 0.0)
        {
         if(gAsianHigh - gAsianLow >= InpMinRangePoints * _Point)
            gAsianRangeReady = true;
        }
      return;
     }

   //--- Inside Asian session: scan closed M15 bars for the current session window.
   //    Start at bar 1 (last closed bar) and walk backwards until we reach a bar
   //    that pre-dates the session reset or exits the session window.
   for(int i = 1; i <= 60; i++)
     {
      datetime barTime = iTime(gSymbol, PERIOD_M15, i);
      if(barTime == 0) break;
      if(gLastAsianReset > 0 && barTime < gLastAsianReset) break;

      MqlDateTime bt;
      TimeToStruct(barTime, bt);
      if(!IsInAsianSession(bt.hour)) break;  // crossed into the previous session

      double hi = iHigh(gSymbol, PERIOD_M15, i);
      double lo = iLow(gSymbol, PERIOD_M15, i);
      if(hi > gAsianHigh) gAsianHigh = hi;
      if(lo < gAsianLow)  gAsianLow  = lo;
     }
  }

//+------------------------------------------------------------------+
//| Check for an Asian range breakout signal on the last closed bar. |
//|                                                                   |
//| Prerequisites: gAsianRangeReady == true, London open window,     |
//|                H1 200 EMA trend alignment, one trade per day.    |
//+------------------------------------------------------------------+
ENUM_MODE_TRADE_SIGNAL CheckAsianBreakoutSignal()
  {
   if(!gAsianRangeReady) return NO_SIGNAL;
   if(gTradedToday)      return NO_SIGNAL;
   if(g_h_ema_h1 == INVALID_HANDLE) return NO_SIGNAL;

   //--- London open window gate
   MqlDateTime t;
   TimeCurrent(t);
   if(t.hour < InpLondonOpenStart || t.hour >= InpLondonOpenEnd)
      return NO_SIGNAL;

   //--- Last closed M15 bar values
   double barClose = iClose(gSymbol, PERIOD_M15, 1);
   if(barClose <= 0.0) return NO_SIGNAL;

   //--- H1 200 EMA at the last closed H1 bar
   double emaH1 = GetIndValue(g_h_ema_h1, 0, 1);
   if(emaH1 == EMPTY_VALUE) return NO_SIGNAL;

   //--- BUY: close breaks above Asian high and is above H1 EMA (uptrend)
   if(barClose > gAsianHigh && barClose > emaH1)
      return BUY_SIGNAL;

   //--- SELL: close breaks below Asian low and is below H1 EMA (downtrend)
   if(barClose < gAsianLow && barClose < emaH1)
      return SELL_SIGNAL;

   return NO_SIGNAL;
  }

//+------------------------------------------------------------------+
//| Main signal dispatcher — called from OnTick() after gate checks. |
//| Refreshes the Asian range then evaluates the breakout signal.    |
//+------------------------------------------------------------------+
ENUM_MODE_TRADE_SIGNAL GetSignal()
  {
   //--- One trade per completed M15 bar
   datetime barTime = iTime(gSymbol, PERIOD_M15, 1);
   if(barTime == gLastBarTraded) return NO_SIGNAL;

   //--- Max simultaneous positions guard
   if(gTotalPositions >= InpMaxPositions) return NO_SIGNAL;

   UpdateAsianRange();
   return CheckAsianBreakoutSignal();
  }
//+------------------------------------------------------------------+
