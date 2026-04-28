from src.ingest.cleaner import clean_markdown


def test_removes_image_links():
    result = clean_markdown("Hello ![cat](images/cat.png) world")
    assert "![" not in result
    assert "images/cat.png" not in result


def test_removes_toc():
    result = clean_markdown("[TOC]\n\n## Section")
    assert "[toc]" not in result.lower()


def test_removes_bare_url():
    result = clean_markdown("Visit https://example.com for more info")
    assert "https://example.com" not in result
    assert "Visit" in result


def test_keeps_markdown_link_intact():
    text = "See [official docs](https://example.com) here"
    result = clean_markdown(text)
    assert "[official docs](https://example.com)" in result


def test_removes_autolink():
    result = clean_markdown("contact <https://example.com> now")
    assert "https://example.com" not in result


def test_collapses_excess_blank_lines():
    result = clean_markdown("A\n\n\n\nB")
    assert "\n\n\n" not in result


def test_empty_string():
    assert clean_markdown("") == ""


def test_preserves_chinese_text():
    text = "這是一段繁體中文內容。\n\n![圖片](img.png)\n\n繼續閱讀。"
    result = clean_markdown(text)
    assert "這是一段繁體中文內容" in result
    assert "繼續閱讀" in result
    assert "![" not in result
