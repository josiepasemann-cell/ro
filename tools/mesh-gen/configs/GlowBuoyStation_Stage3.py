import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _bldg_glow import *


class Config(Glow):
    name = "GlowBuoyStation_Stage3"
    stage = 3
