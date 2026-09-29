import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _bldg_brood import *


class Config(Brood):
    name = "BroodPool_Basic"
    stage = 1
