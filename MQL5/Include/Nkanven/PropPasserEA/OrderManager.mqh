//+------------------------------------------------------------------+
//|                                               OrderManager.mqh   |
//|                        Copyright 2024, Nkondog Anselme Venceslas |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//| Handles order execution with retry logic.                        |
//| SL is placed ATR × InpAtrMultiplier away from entry price.       |
//| TP is SL distance × InpRRRatio (minimum 2:1 by default).         |
//| Falls back to InpDefaultStopLoss / InpDefaultTakeProfit if ATR   |
//| value is unavailable.                                            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nkondog Anselme Venceslas"
#property link      "https://www.mql5.com"

CTrade g_orderTrade;  // CTrade instance for order execution

//+------------------------------------------------------------------+
//| Execute a market order in the direction of 'signal'.             |
//| On success, records bar time so we don't re-enter on same bar.   |
//+------------------------------------------------------------------+
void ExecuteOrder(ENUM_MODE_TRADE_SIGNAL signal)
  {
   if(signal == NO_SIGNAL) return;

   //--- Entry price
   double entryPrice = (signal == BUY_SIGNAL) ? last_tick.ask : last_tick.bid;

   //--- Stop loss distance (ATR-based or fixed fallback)
   double slDistance = 0.0;
   if(InpStopLossMode == SL_AUTO && gAtr > 0.0)
      slDistance = gAtr * InpAtrMultiplier;
   else
      slDistance = InpDefaultStopLoss * _Point;

   //--- Take profit distance
   double tpDistance = 0.0;
   if(InpTakeProfitMode == TP_AUTO && slDistance > 0.0)
      tpDistance = slDistance * InpRRRatio;
   else
      tpDistance = InpDefaultTakeProfit * _Point;

   //--- Calculate SL and TP prices
   double slPrice = 0.0, tpPrice = 0.0;
   if(signal == BUY_SIGNAL)
     {
      slPrice = entryPrice - slDistance;
      tpPrice = entryPrice + tpDistance;
     }
   else
     {
      slPrice = entryPrice + slDistance;
      tpPrice = entryPrice - tpDistance;
     }

   //--- Normalise prices to symbol digits
   slPrice = NormalizeDouble(slPrice, (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS));
   tpPrice = NormalizeDouble(tpPrice, (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS));

   //--- Calculate lot size based on SL distance
   double slPoints = slDistance / _Point;
   if(!CalculateLotSize(slPoints) || gLotSize <= 0.0)
     {
      Print("OrderManager: Lot size calculation failed — skipping order");
      return;
     }

   //--- Configure CTrade
   g_orderTrade.SetExpertMagicNumber(InpMagicNumber);
   g_orderTrade.SetDeviationInPoints(InpSlippage);
   g_orderTrade.SetTypeFilling(ORDER_FILLING_IOC);

   //--- Retry loop
   bool  success  = false;
   for(int attempt = 1; attempt <= gOrderOpRetry && !success; attempt++)
     {
      if(signal == BUY_SIGNAL)
         success = g_orderTrade.Buy(gLotSize, gSymbol, entryPrice, slPrice, tpPrice, InpComment);
      else
         success = g_orderTrade.Sell(gLotSize, gSymbol, entryPrice, slPrice, tpPrice, InpComment);

      if(!success)
        {
         int err = GetLastError();
         Print("OrderManager: Order attempt ", attempt, " failed — Error ", err);

         //--- Switch to FOK filling on second attempt
         if(attempt == 1)
            g_orderTrade.SetTypeFilling(ORDER_FILLING_FOK);

         //--- Refresh price for next attempt
         SymbolInfoTick(gSymbol, last_tick);
         entryPrice = (signal == BUY_SIGNAL) ? last_tick.ask : last_tick.bid;
         if(signal == BUY_SIGNAL)
           {
            slPrice = NormalizeDouble(entryPrice - slDistance, (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS));
            tpPrice = NormalizeDouble(entryPrice + tpDistance, (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS));
           }
         else
           {
            slPrice = NormalizeDouble(entryPrice + slDistance, (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS));
            tpPrice = NormalizeDouble(entryPrice - tpDistance, (int)SymbolInfoInteger(gSymbol, SYMBOL_DIGITS));
           }
        }
     }

   if(success)
     {
      gLastBarTraded = iTime(gSymbol, InpTimeFrame, 1);
      Print("OrderManager: Order placed — ", EnumToString(signal),
            " Lot=", gLotSize,
            " Entry=", entryPrice,
            " SL=", slPrice,
            " TP=", tpPrice);
     }
   else
     {
      Print("OrderManager: All ", gOrderOpRetry, " attempts failed for ",
            EnumToString(signal), " order");
     }
  }
//+------------------------------------------------------------------+
