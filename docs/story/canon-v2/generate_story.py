"""Build only the separate canon-v2 narrative artifacts, preserving v1 content."""
import sys
sys.dont_write_bytecode=True
from build_story_content import finish
import chapter01_source
import chapter02_source
import chapter_03_source

if __name__ == '__main__':
    finish()
