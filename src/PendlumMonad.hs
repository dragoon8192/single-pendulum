module PendlumMonad (
  Pendulum,runPendulum,
  getPhase,getDiffPhase,
  symplecticEvol1
)where
import Data.AffineSpace
import Data.VectorSpace
import Control.Arrow
import Control.Monad
import Control.Monad.Reader
import Control.Monad.State

class (MonadState (Q s,P s) s, MonadReader ((Data s -> (Q s, P s) -> Diff (Q s), Data s -> (Q s, P s) -> Diff (P s)),Data s) s, AffineSpace (Q s), AffineSpace (P s), VectorSpace (Diff (Q s)), VectorSpace (Diff (P s)), DTime s ~ Scalar (Diff (P s)), DTime s ~ Scalar (Diff (Q s)))
  => PhysicalSystemClass s where
  type DTime s :: *
  type Data s :: *
  type Q s :: *
  type P s :: *

  askDiffFunc :: s (Data s -> (Q s, P s) -> Diff (Q s), Data s -> (Q s, P s) -> Diff (P s))
  askDiffFunc = asks fst
  askData :: s (Data s)
  askData = asks snd

  getPhase :: s (Q s, P s)
  getPhase = get
  getQ :: s (Q s)
  getQ = fmap fst getPhase
  getP :: s (P s)
  getP = fmap snd getPhase

  getDiffPhase :: s (Diff (Q s), Diff (P s))
  getDiffPhase = eval2 <$> askDiffFunc <*> askData <*> getPhase
    where
      eval2 (f,g) d pq = (f d pq, g d pq)

  getDqDt :: s (Diff (Q s))
  getDqDt = fmap fst getDiffPhase
  getDpDt :: s (Diff (P s))
  getDpDt = fmap snd getDiffPhase

  evolQ :: DTime s -> s ()
  evolQ dt = do
    dqdt <- getDqDt
    modify $ first (.+^ dt *^ dqdt)
    --modify . first . flip (.+^) . (dt *^) =<< getDqDt
  evolP :: DTime s -> s ()
  evolP dt = do
    dpdt <- getDpDt
    modify $ second (.+^ dt *^ dpdt)

  symplecticEvol1 :: DTime s -> s ()
  symplecticEvol1 dt = do
    evolP dt
    evolQ dt

newtype PhysicalSystem dq dp d q p x = PhysicalSystem (ReaderT ((d -> (q, p) -> dq, d -> (q, p) -> dp), d) (State (q, p)) x)
  deriving (Functor, Applicative, Monad, MonadState (q,p),  MonadReader ((d -> (q, p) -> dq, d -> (q, p) -> dp), d))
runPhysicalSystem :: PhysicalSystem (Diff q) (Diff p) d q p x -> (d -> (q, p) -> Diff q, d -> (q, p) -> Diff p) -> d -> (q, p) -> (x, (q, p))
runPhysicalSystem (PhysicalSystem system) (dqdtFunc, dpdtFunc) d (q, p)
  = runState (runReaderT system ((dqdtFunc, dpdtFunc), d)) (q, p)
execPhysicalSystem :: PhysicalSystem (Diff q) (Diff p) d q p x -> (d -> (q, p) -> Diff q, d -> (q, p) -> Diff p) -> d -> (q, p) -> (q, p)
execPhysicalSystem (PhysicalSystem system) (dqdtFunc, dpdtFunc) d (q, p)
  = execState (runReaderT system ((dqdtFunc, dpdtFunc), d)) (q, p)
--askData :: (AffineSpace q, AffineSpace p, VectorSpace (Diff q), VectorSpace (Diff p)) => PhysicalSystem d q p d
--askData = PhysicalSystem $ asks snd
--askDiffFunc :: (AffineSpace q, AffineSpace p, VectorSpace (Diff q), VectorSpace (Diff p))
--  => PhysicalSystem d q p (d -> (q, p) -> Diff q, d -> (q, p) -> Diff p)
--askDiffFunc = PhysicalSystem $ asks fst
--
--instance (AffineSpace q, AffineSpace p, VectorSpace (Diff q), VectorSpace (Diff p) , dq ~ Diff q, dp ~ Diff p) =>  MonadReader ((d -> (q, p) -> dq, d -> (q, p) -> dp), d) (PhysicalSystem d q p)

instance (AffineSpace q, AffineSpace p, dq ~ Diff q, dp ~ Diff p, VectorSpace dq, VectorSpace dp, Scalar dq ~ Scalar dp)
  => PhysicalSystemClass (PhysicalSystem dq dp d q p) where
  type DTime (PhysicalSystem dq dp d q p) = Scalar dq
  type Data (PhysicalSystem dq dp d q p) = d
  type Q (PhysicalSystem dq dp d q p) = q
  type P (PhysicalSystem dq dp d q p) = p

type Pendulum = PhysicalSystem Double Double (Double,Double) Double Double
runPendulum :: Pendulum x -> (Double, Double) -> (Double, Double) -> (x, (Double, Double))
runPendulum system = runPhysicalSystem system (dqdt, dpdt)
  where
    dqdt (m, l) (q, p) = p / (m * l * l)
    dpdt (m, l) (q, p) = - m * 9.8 * l * sin q
