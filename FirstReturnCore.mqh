// Chronological state machine. Only completed bars commit this state.
struct FRParams
{
   int pairBars, expiryBars;
   double slopeATR, touchATR, departureATR;
};
struct FRBar
{
   int index, cross, breakout;
   double fast, slow, fastPast, slowPast, atr;
   double low, high, close;
   bool rangeValid;
};
struct FRState
{
   int crossDir, crossBar, breakDir, breakBar;
   bool consumed, departed;
};
void FRReset(FRState &s)
{
   s.crossDir=0; s.crossBar=-1000000;
   s.breakDir=0; s.breakBar=-1000000;
   s.consumed=false; s.departed=false;
}
bool FRReady(FRState &s, FRBar &b, FRParams &p)
{
   if(s.crossDir==0 || s.consumed || s.breakDir!=s.crossDir) return false;
   if(MathAbs(s.crossBar-s.breakBar)>p.pairBars) return false;
   if(b.index-s.breakBar>p.expiryBars) return false;
   if(b.index<=MathMax(s.crossBar,s.breakBar)) return false;
   return true;
}
bool FRTrend(FRState &s, FRBar &b, FRParams &p)
{
   if(b.atr<=0) return false;
   return s.crossDir*(b.fast-b.slow)>0 &&
          s.crossDir*(b.fast-b.fastPast)>b.atr*p.slopeATR &&
          s.crossDir*(b.slow-b.slowPast)>b.atr*p.slopeATR;
}
// cross/breakout fields must be zero for provisional tick evaluation.
// Return direction on first touch only. Departure is committed after touch check,
// so an OHLC bar cannot create both departure and return in unknown tick order.
int FRCommit(FRState &s, FRBar &b, FRParams &p, bool allowTouch)
{
   if(b.cross!=0)
   {
      s.crossDir=b.cross; s.crossBar=b.index;
      s.consumed=false; s.departed=false;
   }
   if(s.breakDir!=0 && b.index-s.breakBar>p.expiryBars)
   { s.breakDir=0; s.departed=false; }
   if(b.rangeValid && b.breakout!=0 &&
      (s.breakDir==0 || s.breakDir!=b.breakout))
   {
      s.breakDir=b.breakout; s.breakBar=b.index; s.departed=false;
   }
   if(!FRReady(s,b,p)) return 0;
   if(allowTouch && s.departed && FRTrend(s,b,p))
   {
      double lower=b.fast-b.atr*p.touchATR;
      double upper=b.fast+b.atr*p.touchATR;
      // Intersect the band; a gap beyond the entire band is not a touch.
      if(b.high>=lower && b.low<=upper)
      { s.consumed=true; return s.crossDir; }
   }
   if(FRTrend(s,b,p) && s.crossDir*(b.close-b.fast)>=b.atr*p.departureATR)
      s.departed=true;
   return 0;
}
// Tick evaluation and pre-start historical approximation may detect a touch.
int FRStep(FRState &s, FRBar &b, FRParams &p)
{
   return FRCommit(s,b,p,true);
}
