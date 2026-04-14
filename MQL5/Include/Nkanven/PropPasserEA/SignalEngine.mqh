//+------------------------------------------------------------------+
//|                                               SignalEngine.mqh   |
//|                        Copyright 2024, Nkondog Anselme Venceslas |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Two selectable strategies:                                        |
//|   STRATEGY_EMA_PINBAR    — 50 EMA trend filter + Pin Bar entry   |
//|   STRATEGY_EMA_CROSSOVER — 8/21 EMA crossover + RSI filter       |
//|                                                                  |
//| Indicator handles are created in the main EA and assigned here   |
//| via extern pointers: g_ema_trend, g_ema_fast, g_ema_slow.        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nkondog Anselme Venceslas"
#property link      "https://www.mql5.com"

//--- Indicator handle references (set by PropPasserEA.mq5 OnInit)
int g_h_ema_trend = INVALID_HANDLE;
int g_h_ema_fast  = INVALID_HANDLE;
int g_h_ema_slow  = INVALID_HANDLE;
int g_h_rsi       = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Read a single double from an indicator buffer                    |
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
//| Strategy 1: EMA Trend + Pin Bar                                  |
//|                                                                  |
//| A pin bar is identified by a long wick relative to total range.  |
//| Bullish pin: lower wick >= InpPinBarWickPct% of range AND        |
//|              close above 50 EMA (trend is up).                   |
//| Bearish pin: upper wick >= InpPinBarWickPct% of range AND        |
//|              close below 50 EMA (trend is down).                 |
//+------------------------------------------------------------------+
ENUM_MODE_TRADE_SIGNAL CheckPinBarSignal()
  {
   if(g_h_ema_trend == INVALID_HANDLE) return NO_SIGNAL;

   //--- Completed candle (index 1)
   double candleOpen  = iOpen(gSymbol,  InpTimeFrame, 1);
   double candleHigh  = iHigh(gSymbol,  InpTimeFrame, 1);
   double candleLow   = iLow(gSymbol,   InpTimeFrame, 1);
   double candleClose = iClose(gSymbol, InpTimeFrame, 1);

   double range = candleHigh - candleLow;

   //--- Reject tiny candles / doji
   if(range < InpMinCandlePoints * _Point)
      return NO_SIGNAL;

   double bodyHigh  = MathMax(candleOpen, candleClose);
   double bodyLow   = MathMin(candleOpen, candleClose);
   double upperWick = candleHigh - bodyHigh;
   double lowerWick = bodyLow - candleLow;

   //--- Trend EMA value at the completed candle
   double emaValue = GetIndValue(g_h_ema_trend, 0, 1);
   if(emaValue == EMPTY_VALUE) return NO_SIGNAL;

   double wickThreshold = range * InpPinBarWickPct / 100.0;

   //--- Bullish pin bar: long lower wick, price above trend EMA
   if(lowerWick >= wickThreshold && candleClose > emaValue)
      return BUY_SIGNAL;

   //--- Bearish pin bar: long upper wick, price below trend EMA
   if(upperWick >= wickThreshold && candleClose < emaValue)
      return SELL_SIGNAL;

   return NO_SIGNAL;
  }

//+------------------------------------------------------------------+
//| Strategy 2: EMA Crossover + RSI Filter                           |
//|                                                                  |
//| Bullish: fast EMA crossed above slow EMA on bar 1 vs bar 2,      |
//|          RSI > InpRsiOversold (not oversold territory).          |
//| Bearish: fast EMA crossed below slow EMA on bar 1 vs bar 2,      |
//|          RSI < InpRsiOverbought (not overbought territory).       |
//+------------------------------------------------------------------+
ENUM_MODE_TRADE_SIGNAL CheckEmaCrossoverSignal()
  {
   if(g_h_ema_fast == INVALID_HANDLE || g_h_ema_slow == INVALID_HANDLE ||
      g_h_rsi == INVALID_HANDLE)
      return NO_SIGNAL;

   double fastEma1 = GetIndValue(g_h_ema_fast, 0, 1);
   double fastEma2 = GetIndValue(g_h_ema_fast, 0, 2);
   double slowEma1 = GetIndValue(g_h_ema_slow, 0, 1);
   double slowEma2 = GetIndValue(g_h_ema_slow, 0, 2);
   double rsi      = GetIndValue(g_h_rsi,      0, 1);

   if(fastEma1 == EMPTY_VALUE || fastEma2 == EMPTY_VALUE ||
      slowEma1 == EMPTY_VALUE || slowEma2 == EMPTY_VALUE ||
      rsi == EMPTY_VALUE)
      return NO_SIGNAL;

   //--- Bullish crossover: fast crossed above slow
   if(fastEma2 <= slowEma2 && fastEma1 > slowEma1 && rsi > InpRsiOversold)
      return BUY_SIGNAL;

   //--- Bearish crossover: fast crossed below slow
   if(fastEma2 >= slowEma2 && fastEma1 < slowEma1 && rsi < InpRsiOverbought)
      return SELL_SIGNAL;

   return NO_SIGNAL;
  }

//+------------------------------------------------------------------+
//| Main signal dispatcher — called from OnTick.                     |
//| Returns NO_SIGNAL if:                                            |
//|   - We already traded this bar                                   |
//|   - Max positions already open                                   |
//|   - Trading is outside allowed hours                             |
//+------------------------------------------------------------------+
ENUM_MODE_TRADE_SIGNAL GetSignal()
  {
   //--- FIX v1.01: anchor to bar[0] (current live candle) — bar[1] caused
   //    double entries at every new candle open. See OrderManager.mqh for
   //    the matching change.
   datetime barTime = iTime(gSymbol, InpTimeFrame, 0);
   if(barTime == gLastBarTraded)
      return NO_SIGNAL;

   //--- Max simultaneous positions guard
   if(gTotalPositions >= InpMaxPositions)
      return NO_SIGNAL;

   //--- Dispatch to selected strategy
   if(InpStrategy == STRATEGY_EMA_PINBAR)
      return CheckPinBarSignal();

   if(InpStrategy == STRATEGY_EMA_CROSSOVER)
      return CheckEmaCrossoverSignal();

   return NO_SIGNAL;
  }
//+------------------------------------------------------------------+
