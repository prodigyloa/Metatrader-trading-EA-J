//+------------------------------------------------------------------+
//|  MAConvEA.mq5                                                    |
//|  Copyright 2024                                                  |
//|  Expert Advisor driven by MAConvergenceSignal indicator buffers  |
//+------------------------------------------------------------------+
//  SETUP: compile MAConvergenceSignal.mq5 into MQL5\Indicators\ first.
//  This EA reads buffer 0 (bull) and buffer 1 (bear) at bar[1] on
//  every new bar close. A non-EMPTY_VALUE in either buffer fires a
//  trade. An opposite signal flips the position.
//+------------------------------------------------------------------+
#property copyright "2024"
#property link      ""
#property version   "1.00"
#property description "Trades MAConvergenceSignal bull/bear arrows"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//--- ── Indicator parameters (must match what MAConvergenceSignal expects) ──
input group "=== Indicator Settings ==="
input int              InpFastPeriod        = 5;              // Fast MA Period
input int              InpSlowPeriod        = 14;             // Slow MA Period
input ENUM_MA_METHOD   InpMAMethod          = MODE_EMA;       // MA Method
input int              InpLookback          = 10;             // Lookback for extreme
input double           InpExtremeMultiplier = 1.5;            // Extreme multiplier

//--- ── Trade parameters ──────────────────────────────────────────────────
input group "=== Trade Settings ==="
input double           InpLotSize           = 0.1;            // Lot size
input int              InpStopLossPts       = 200;            // Stop loss (points, 0=off)
input int              InpTakeProfitPts     = 400;            // Take profit (points, 0=off)
input int              InpMaxSpreadPts      = 30;             // Max spread filter (points, 0=off)
input int              InpMagicNumber       = 20240001;       // Magic number
input string           InpTradeComment      = "MAConvEA";     // Order comment

//--- ── Position behaviour ────────────────────────────────────────────────
input group "=== Position Behaviour ==="
input bool             InpFlipOnReverse     = true;           // Close & flip on opposite signal
input bool             InpOneTradeOnly      = true;           // Skip signal if same-direction trade exists

//--- Globals
CTrade   trade;
int      hSignal     = INVALID_HANDLE;
datetime lastBarTime = 0;             // tracks the last processed bar open time

//+------------------------------------------------------------------+
//| Normalise a price to the symbol's tick size                      |
//+------------------------------------------------------------------+
double NormalisePrice(double price)
  {
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0) return NormalizeDouble(price, _Digits);
   return NormalizeDouble(MathRound(price / tick) * tick, _Digits);
  }

//+------------------------------------------------------------------+
//| Count open positions for this EA on this symbol by direction     |
//+------------------------------------------------------------------+
bool HasPosition(ENUM_POSITION_TYPE dir)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == dir) return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Close all EA positions on this symbol (optionally filter by dir) |
//+------------------------------------------------------------------+
void ClosePositions(ENUM_POSITION_TYPE dir = -1)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if((int)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(dir != (ENUM_POSITION_TYPE)-1 &&
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != dir) continue;
      trade.PositionClose(PositionGetTicket(i));
     }
  }

//+------------------------------------------------------------------+
//| Open a market order with optional SL/TP                         |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl  = 0.0, tp = 0.0;
   double pts = _Point;

   if(type == ORDER_TYPE_BUY)
     {
      sl = (InpStopLossPts   > 0) ? NormalisePrice(ask - InpStopLossPts   * pts) : 0.0;
      tp = (InpTakeProfitPts > 0) ? NormalisePrice(ask + InpTakeProfitPts * pts) : 0.0;
      trade.Buy(InpLotSize, _Symbol, ask, sl, tp, InpTradeComment);
     }
   else
     {
      sl = (InpStopLossPts   > 0) ? NormalisePrice(bid + InpStopLossPts   * pts) : 0.0;
      tp = (InpTakeProfitPts > 0) ? NormalisePrice(bid - InpTakeProfitPts * pts) : 0.0;
      trade.Sell(InpLotSize, _Symbol, bid, sl, tp, InpTradeComment);
     }
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Attach to the compiled indicator — pass false for InpShowDashboard
   // so we don't spawn a redundant chart panel. The remaining three
   // parameters (InpCorner, InpDashX, InpDashY) use indicator defaults.
   hSignal = iCustom(_Symbol, _Period, "MAConvergenceSignal",
                     InpFastPeriod, InpSlowPeriod, InpMAMethod,
                     InpLookback, InpExtremeMultiplier,
                     false,                  // InpShowDashboard
                     CORNER_RIGHT_UPPER, 15, 20);

   if(hSignal == INVALID_HANDLE)
     {
      Print("MAConvEA: failed to load MAConvergenceSignal indicator. ",
            "Ensure it is compiled in MQL5\\Indicators\\");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(10);           // allow up to 1 pip slippage
   trade.SetTypeFilling(ORDER_FILLING_FOK);  // adjust to broker if needed

   Print("MAConvEA initialised — Magic:", InpMagicNumber,
         " Lots:", InpLotSize,
         " SL:", InpStopLossPts, "pts  TP:", InpTakeProfitPts, "pts");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hSignal != INVALID_HANDLE)
      IndicatorRelease(hSignal);
  }

//+------------------------------------------------------------------+
//| OnTick — bar-close driven logic                                  |
//+------------------------------------------------------------------+
void OnTick()
  {
   // ── New-bar gate: only act once per closed bar ──────────────────
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == lastBarTime) return;
   lastBarTime = barTime;

   // ── Spread filter ───────────────────────────────────────────────
   if(InpMaxSpreadPts > 0)
     {
      long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spreadPts > InpMaxSpreadPts)
        {
         Print("MAConvEA: spread ", spreadPts, " > max ", InpMaxSpreadPts, " — skip");
         return;
        }
     }

   // ── Read indicator buffers at bar[1] (last closed bar) ──────────
   // We copy 3 values (bars 0,1,2) so index 1 = bar[1].
   double bull[3], bear[3];
   ArraySetAsSeries(bull, true);
   ArraySetAsSeries(bear, true);

   if(CopyBuffer(hSignal, 0, 0, 3, bull) < 3) return;  // buffer 0 = BullBuffer
   if(CopyBuffer(hSignal, 1, 0, 3, bear) < 3) return;  // buffer 1 = BearBuffer

   bool buySignal  = (bull[1] != EMPTY_VALUE);
   bool sellSignal = (bear[1] != EMPTY_VALUE);

   // ── Execute trade logic ─────────────────────────────────────────
   if(buySignal)
     {
      if(InpFlipOnReverse) ClosePositions(POSITION_TYPE_SELL);
      if(!InpOneTradeOnly || !HasPosition(POSITION_TYPE_BUY))
        {
         Print("MAConvEA: BUY signal on ", _Symbol, " at ", SymbolInfoDouble(_Symbol, SYMBOL_ASK));
         OpenTrade(ORDER_TYPE_BUY);
        }
     }
   else if(sellSignal)
     {
      if(InpFlipOnReverse) ClosePositions(POSITION_TYPE_BUY);
      if(!InpOneTradeOnly || !HasPosition(POSITION_TYPE_SELL))
        {
         Print("MAConvEA: SELL signal on ", _Symbol, " at ", SymbolInfoDouble(_Symbol, SYMBOL_BID));
         OpenTrade(ORDER_TYPE_SELL);
        }
     }
  }
//+------------------------------------------------------------------+
