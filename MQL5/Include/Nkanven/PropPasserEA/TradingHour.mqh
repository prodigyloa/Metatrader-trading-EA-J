//+------------------------------------------------------------------+
//|                                                 TradingHour.mqh  |
//|                        Copyright 2024, Nkondog Anselme Venceslas |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nkondog Anselme Venceslas"
#property link      "https://www.mql5.com"

//+------------------------------------------------------------------+
//| Check whether the current broker time falls within the allowed   |
//| trading session. Sets gIsOperatingHours accordingly.             |
//| If InpUseTradingHours is false, always allows trading.           |
//+------------------------------------------------------------------+
void CheckOperationHours()
  {
   if(!InpUseTradingHours)
     {
      gIsOperatingHours = true;
      return;
     }

   MqlDateTime now;
   TimeCurrent(now);

   int currentHour = now.hour;

   if(InpSessionStart <= InpSessionEnd)
     {
      //--- Normal window: e.g. 07:00 – 21:00
      gIsOperatingHours = (currentHour >= InpSessionStart && currentHour < InpSessionEnd);
     }
   else
     {
      //--- Overnight window: e.g. 22:00 – 06:00 (crosses midnight)
      gIsOperatingHours = (currentHour >= InpSessionStart || currentHour < InpSessionEnd);
     }
  }
//+------------------------------------------------------------------+
