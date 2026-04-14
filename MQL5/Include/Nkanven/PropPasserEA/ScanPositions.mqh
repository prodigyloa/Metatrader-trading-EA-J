//+------------------------------------------------------------------+
//|                                               ScanPositions.mqh  |
//|                        Copyright 2024, Nkondog Anselme Venceslas |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nkondog Anselme Venceslas"
#property link      "https://www.mql5.com"

//+------------------------------------------------------------------+
//| Count all open positions matching this EA's symbol and magic     |
//+------------------------------------------------------------------+
void ScanPositions()
  {
   gTotalBuyPositions  = 0;
   gTotalSellPositions = 0;
   gTotalPositions     = 0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL)  == gSymbol &&
            PositionGetInteger(POSITION_MAGIC)  == InpMagicNumber)
           {
            gTotalPositions++;
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               gTotalBuyPositions++;
            else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
               gTotalSellPositions++;
           }
        }
     }
  }
//+------------------------------------------------------------------+
