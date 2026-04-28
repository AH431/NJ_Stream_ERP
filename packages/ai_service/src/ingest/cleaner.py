import re


def clean_markdown(text: str) -> str:
    """Remove noise: image links, bare URLs, [toc], excess blank lines."""
    # Remove image links: ![alt](url)
    text = re.sub(r'!\[[^\]]*\]\([^)]*\)', '', text)
    # Remove [toc] / [TOC]
    text = re.sub(r'\[toc\]', '', text, flags=re.IGNORECASE)
    # Remove autolinks <https://...>
    text = re.sub(r'<https?://[^>]+>', '', text)
    # Remove bare URLs — negative lookbehind skips URLs inside markdown links ](url)
    text = re.sub(r'(?<!\()\bhttps?://\S+', '', text)
    # Collapse 3+ blank lines into 2
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()
