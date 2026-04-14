//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh  |
//|                        Copyright 2024, Nkondog Anselme Venceslas |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nkondog Anselme Venceslas"
#property link      "https://www.mql5.com"

//+------------------------------------------------------------------+
//| Calculate lot size based on risk parameters.                     |
//|                                                                  |
//| SL_points: stop loss distance in points (as returned by Point()) |
//| Sets gLotSize. Returns false if lot size is too small to trade.  |
//+------------------------------------------------------------------+
bool CalculateLotSize(double SL_points)
  {
   if(InpRiskDefaultSize == RISK_DEFAULT_FIXED)
     {
      gLotSize = InpDefaultLotSize;
     }
   else // RISK_DEFAULT_AUTO
     {
      if(SL_points <= 0)
        {
         gLotSize = InpDefaultLotSize;
        }
      else
        {
         double riskBase = 0.0;
         if(InpRiskBase == RISK_BASE_BALANCE)
            riskBase = AccountInfoDouble(ACCOUNT_BALANCE);
         else if(InpRiskBase == RISK_BASE_EQUITY)
            riskBase = AccountInfoDouble(ACCOUNT_EQUITY);
         else if(InpRiskBase == RISK_BASE_FREEMARGIN)
            riskBase = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

         //--- Dollar value of 1 tick movement for 1 lot
         double tickValue = SymbolInfoDouble(gSymbol, SYMBOL_TRADE_TICK_VALUE);
         if(tickValue <= 0)
           {
            Print("RiskManager: TickValue is 0 for ", gSymbol, " — using default lot size");
            gLotSize = InpDefaultLotSize;
           }
         else
           {
            //--- Risk amount / (SL_points * TickValue)
            gLotSize = (riskBase * InpMaxRiskPerTrade / 100.0) / (SL_points * tickValue);
           }
        }
     }

   //--- Normalize to the broker's volume step
   double volStep = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_STEP);
   if(volStep > 0)
      gLotSize = MathFloor(gLotSize / volStep) * volStep;

   //--- Cap at broker maximum
   double volMax = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_MAX);
   if(gLotSize > volMax)
      gLotSize = volMax;

   //--- Cap at user maximum
   if(gLotSize > InpMaxLotSize)
      gLotSize = InpMaxLotSize;

   //--- Reject if below minimum
   double volMin = SymbolInfoDouble(gSymbol, SYMBOL_VOLUME_MIN);
   if(gLotSize < InpMinLotSize || gLotSize < volMin)
     {
      Print("RiskManager: Lot size too small (", gLotSize, ") — skipping trade");
      gLotSize = 0;
      return false;
     }

   return true;
  }
//+------------------------------------------------------------------+
