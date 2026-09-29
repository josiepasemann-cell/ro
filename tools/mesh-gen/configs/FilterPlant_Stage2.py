import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _bldg_filter import *


class Config(Filter):
    name = "FilterPlant_Stage2"
    stage = 2
