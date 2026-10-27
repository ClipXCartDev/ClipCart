"""Turning a creator's subtitle file into caption layers.

A creator arrives with an SRT next to their clip; before this the only way in
was to type every caption and both its timestamps by hand. So the parser is
the whole feature, and the ways it can quietly go wrong — a timestamp read as
the wrong number, a caption landing outside the footage, a file from a writer
that formats slightly differently — are the ways the feature fails.
"""
from __future__ import annotations

import pytest

from app.services.subtitles import MAX_CAPTIONS, SubtitleError, parse

SRT = """1
00:00:01,000 --> 00:00:03,500
First line

2
00:00:04,000 --> 00:00:06,250
Second line
over two rows
"""


def test_a_plain_srt_becomes_captions_in_order():
    caps = parse(SRT)
    assert [c["t"] for c in caps] == ["First line", "Second line over two rows"]
    assert caps[0]["s"] == 1.0 and caps[0]["e"] == 3.5
    assert caps[1]["s"] == 4.0 and caps[1]["e"] == 6.25


def test_every_caption_arrives_ready_to_render():
    # The editor reads these straight into SubtitleSegment; a missing key is an
    # exception in the middle of a creator's session.
    for c in parse(SRT):
        for key in ("t", "s", "e", "c", "fs", "dx", "dy", "al", "k", "z"):
            assert key in c, f"missing {key}"
        assert c["k"] == "text"


def test_fractions_are_read_as_fractions_of_a_second():
    # ",5" is half a second. Read as milliseconds it would be 5ms and every
    # caption would be a frame long.
    caps = parse("1\n00:00:01,5 --> 00:00:02,25\nhi\n")
    assert caps[0]["s"] == 1.5
    assert caps[0]["e"] == 2.25


def test_hours_count():
    caps = parse("1\n01:02:03,000 --> 01:02:04,000\nlate\n")
    assert caps[0]["s"] == 3723.0


def test_webvtt_is_accepted_too():
    vtt = """WEBVTT

NOTE this is a comment

00:00:02.000 --> 00:00:04.000
From a VTT
"""
    caps = parse(vtt)
    assert len(caps) == 1
    assert caps[0]["t"] == "From a VTT"
    assert caps[0]["s"] == 2.0


def test_a_cue_with_no_id_line_still_parses():
    caps = parse("00:00:01,000 --> 00:00:02,000\nno id\n")
    assert [c["t"] for c in caps] == ["no id"]


def test_windows_line_endings_and_a_byte_order_mark():
    caps = parse("﻿1\r\n00:00:01,000 --> 00:00:02,000\r\nwindows\r\n")
    assert [c["t"] for c in caps] == ["windows"]


def test_inline_tags_are_stripped_not_shown():
    caps = parse("1\n00:00:01,000 --> 00:00:02,000\n<i>slanted</i> and <b>bold</b>\n")
    assert caps[0]["t"] == "slanted and bold"


def test_captions_come_back_in_time_order_whatever_order_they_were_written():
    caps = parse(
        "1\n00:00:09,000 --> 00:00:10,000\nlast\n\n"
        "2\n00:00:01,000 --> 00:00:02,000\nfirst\n"
    )
    assert [c["t"] for c in caps] == ["first", "last"]
    assert [c["z"] for c in caps] == [0.0, 1.0]


# ---- the clip's length is a real boundary --------------------------------

def test_a_caption_past_the_end_of_the_clip_is_dropped():
    # Its window lies outside the footage: it would render nowhere, and read
    # as the file having silently failed.
    caps = parse(SRT, duration=3.0)
    assert [c["t"] for c in caps] == ["First line"]


def test_a_caption_that_overruns_the_end_is_trimmed_to_it():
    caps = parse(SRT, duration=5.0)
    assert caps[-1]["e"] == 5.0


def test_without_a_duration_nothing_is_dropped():
    assert len(parse(SRT)) == 2


# ---- malformed input is a message, not a crash ---------------------------

def test_an_empty_file_says_so():
    with pytest.raises(SubtitleError):
        parse("")
    with pytest.raises(SubtitleError):
        parse("   \n\n ")


def test_a_file_with_no_timings_explains_what_was_expected():
    with pytest.raises(SubtitleError) as e:
        parse("just some notes\nand more notes\n")
    assert "-->" in str(e.value)


def test_a_cue_with_no_text_is_skipped_rather_than_making_a_blank_caption():
    caps = parse(
        "1\n00:00:01,000 --> 00:00:02,000\n\n\n"
        "2\n00:00:03,000 --> 00:00:04,000\nreal\n"
    )
    assert [c["t"] for c in caps] == ["real"]


def test_a_zero_length_cue_is_given_a_window_rather_than_dropped():
    # Some writers emit end == start. Dropping it would lose what the creator
    # wrote; leaving it would render nothing.
    caps = parse("1\n00:00:05,000 --> 00:00:05,000\nblink\n")
    assert caps[0]["e"] > caps[0]["s"]


def test_a_very_long_file_is_capped_rather_than_making_an_unusable_timeline():
    big = "".join(
        f"{i}\n00:00:{i % 60:02d},000 --> 00:00:{(i % 60) + 1:02d},000\nline {i}\n\n"
        for i in range(1, MAX_CAPTIONS + 50)
    )
    assert len(parse(big)) <= MAX_CAPTIONS
