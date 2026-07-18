import re
from pathlib import Path

def test_codebase():
    main_dart_path = Path("lib/main.dart")
    code = main_dart_path.read_text(encoding="utf-8")
    
    # 1. Check for cache maps setup
    assert "stepSearchCache" in code
    assert "stepUrlCache" in code
    print("Caches definitions found in lib/main.dart.")
    
    # 2. Check for normalization function definition
    assert "normalizeQueryOrUrl" in code
    print("normalizeQueryOrUrl function found in lib/main.dart.")
    
    # 3. Check for consecutiveMalformedTags check
    assert "consecutiveMalformedTags" in code
    assert "malformed_tag" in code
    print("consecutiveMalformedTags tracking found in lib/main.dart.")
    
    # 4. Check for absolute ceiling and limit string
    assert "loopCount < 30" in code
    assert "step exceeded safety ceiling of 30 tool calls without completing" in code
    print("Safety ceiling of 30 turns found in lib/main.dart.")
    
    # 5. Check for global budget constant and check loops
    assert "globalTimeBudget" in code
    assert "getGlobalElapsed()" in code
    assert "exceeded global time budget" in code
    print("Global time budget tracking found in lib/main.dart.")
    
    # 6. Check for zero-novelty warning nudge
    assert "The last $zeroNoveltyStreak sources added no new information" in code
    assert "Evidence saturation reached" in code
    print("Zero novelty nudges and saturation limit checks found in lib/main.dart.")
    
    print("\nAll codebase circuit breaker static assertions passed!")

if __name__ == "__main__":
    test_codebase()
