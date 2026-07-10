"""
AI/ML Intelligence Module for Autobuilder
Provides intelligent SCM resolution, auto-fix, and predictive capabilities
"""

__version__ = "1.0.0"

from .scm_pattern_learner import SCMPatternLearner
from .auto_fixer import AutoFixer
from .url_validator import SmartURLValidator

__all__ = [
    'SCMPatternLearner',
    'AutoFixer',
    'SmartURLValidator',
]
