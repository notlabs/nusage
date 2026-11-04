# One check's state: pass, skip, cancel, fail, pending or unknown.
def check-state [check: record] {
    if $check.__typename == CheckRun {
        if $check.status != COMPLETED { return pending }
        match $check.conclusion {
            SUCCESS => "pass"
            NEUTRAL | SKIPPED => "skip"
            CANCELLED => "cancel"
            ACTION_REQUIRED | TIMED_OUT | FAILURE | STARTUP_FAILURE | STALE => "fail"
            _ => "unknown"
        }
    } else {
        match $check.state {
            SUCCESS => "pass"
            EXPECTED | PENDING => "pending"
            ERROR | FAILURE => "fail"
            _ => "unknown"
        }
    }
}

# Summarize the current-head checks returned by gh's typed PR wrapper.
export def report [prs: list<record>] {
    $prs | sort-by number | each {|pr|
        let checks = $pr.statusCheckRollup | default [] | each {|check|
            {
                name: ($check.name? | default $check.context?)
                state: (check-state $check)
                url: ($check.detailsUrl? | default $check.targetUrl?)
            }
        }
        {
            number: $pr.number
            title: $pr.title
            base: $pr.baseRefName
            depends_on: ($prs | where {|parent| not $parent.isCrossRepository and $parent.headRefName == $pr.baseRefName} | get number)
            draft: $pr.isDraft
            review: $pr.reviewDecision
            mergeable: $pr.mergeable
            merge_state: $pr.mergeStateStatus
            passed: ($checks | where state == pass | length)
            failed: ($checks | where state == fail | length)
            pending: ($checks | where state == pending | length)
            cancelled: ($checks | where state == cancel | length)
            skipped: ($checks | where state == skip | length)
            unknown: ($checks | where state == unknown | length)
            head_sha: $pr.headRefOid
            checks: $checks
            url: $pr.url
        }
    }
}
