from __future__ import annotations


def format_bytes(value: int | float | None) -> str:
    number = float(value or 0)
    if number < 0:
        number = 0
    units = ["B", "K", "M", "G", "T"]
    index = 0
    while number >= 1024 and index < len(units) - 1:
        number /= 1024
        index += 1
    if index == 0:
        return f"{int(number)}B"
    if number >= 10:
        return f"{number:.1f}{units[index]}".replace(".0", "")
    return f"{number:.1f}{units[index]}"


def format_table(report: dict) -> str:
    lines = []
    totals = report.get("totals") or {}
    lines.append(
        "cache {cache}  stale {stale}  review {review}  total {total}".format(
            cache=format_bytes(totals.get("reclaimableCache")),
            stale=format_bytes(totals.get("reclaimableStale")),
            review=format_bytes(totals.get("reclaimableReview")),
            total=format_bytes(totals.get("bytes")),
        )
    )
    lines.append("")
    lines.append(f"{'ID':<28} {'CLASS':<8} {'SIZE':>8}  SUMMARY")
    for tool in report.get("tools") or []:
        lines.append(f"# {tool.get('name')} ({tool.get('status')})")
        for item in tool.get("items") or []:
            lines.append(
                f"{item.get('id', ''):<28} {item.get('class', ''):<8} {format_bytes(item.get('bytes')):>8}  {item.get('summary', '')}"
            )
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"
