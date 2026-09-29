import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _bldg_angler import *


class Config(Angler):
    name = "AnglerfishTower"
    stage = 1
