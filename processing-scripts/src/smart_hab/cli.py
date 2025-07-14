import smart_hab.about as _about
import smart_hab.clip as _clip
import smart_hab.convert_shape as _convert_shape
import smart_hab.kmeans_classify as _kmeans_classify
import smart_hab.kmeans_fit as _kmeans_fit
import smart_hab.mask as _mask
import smart_hab.norm_diff as _norm_diff
import smart_hab.plot as _plot
import smart_hab.select_bands as _select_bands

def about():
  args = _about.parse_args()
  _about.main(args)

def clip():
  args = _clip.parse_args()
  _clip.main(args)

def convert_shape():
  args = _convert_shape.parse_args()
  _convert_shape.main(args)

def kmeans_classify():
  args = _kmeans_classify.parse_args()
  _kmeans_classify.main(args)

def kmeans_fit():
  args = _kmeans_fit.parse_args()
  _kmeans_fit.main(args)

def mask():
  args = _mask.parse_args()
  _mask.main(args)

def plot():
  args = _plot.parse_args()
  _plot.main(args)

def norm_diff():
  args = _norm_diff.parse_args()
  _norm_diff.main(args)

def select_bands():
  args = _select_bands.parse_args()
  _select_bands.main(args)
