use crate::matching::rank_fuzzy_by;
use std::collections::BTreeSet;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum QueryResolution<T> {
    Match(T),
    NotFound,
    Ambiguous(Vec<String>),
}

pub(crate) fn resolve_query<T, Candidates, ExactKeys, ExactIter, Score, TieBreaker, Label>(
    query: &str,
    candidates: Candidates,
    exact_keys: ExactKeys,
    score: Score,
    tie_breaker: TieBreaker,
    label: Label,
) -> QueryResolution<T>
where
    T: Clone,
    Candidates: IntoIterator<Item = T>,
    ExactKeys: Fn(&T) -> ExactIter,
    ExactIter: IntoIterator,
    ExactIter::Item: AsRef<str>,
    Score: Fn(&T, &str) -> Option<i64>,
    TieBreaker: Fn(&T) -> &str,
    Label: Fn(&T) -> String,
{
    let candidates = candidates.into_iter().collect::<Vec<_>>();
    let mut exact_matches = Vec::new();
    let mut seen = BTreeSet::new();
    for candidate in &candidates {
        if exact_keys(candidate)
            .into_iter()
            .any(|key| key.as_ref() == query)
        {
            let candidate_label = label(candidate);
            if seen.insert(candidate_label.clone()) {
                exact_matches.push((candidate_label, candidate.clone()));
            }
        }
    }
    match exact_matches.as_slice() {
        [(_, candidate)] => return QueryResolution::Match(candidate.clone()),
        [] => {}
        _ => {
            return QueryResolution::Ambiguous(
                exact_matches
                    .into_iter()
                    .map(|(candidate_label, _)| candidate_label)
                    .collect(),
            );
        }
    }

    let scored = rank_fuzzy_by(query, candidates, score, tie_breaker);
    match scored.as_slice() {
        [] => QueryResolution::NotFound,
        [ranked, ..] => {
            let top_score = ranked.score;
            let ambiguous = scored
                .iter()
                .take_while(|ranked| ranked.score == top_score)
                .map(|ranked| label(&ranked.item))
                .collect::<Vec<_>>();
            if ambiguous.len() == 1 {
                QueryResolution::Match(ranked.item.clone())
            } else {
                let partial = partial_matches(query, &scored, &exact_keys, &label);
                if partial.is_empty() {
                    QueryResolution::Ambiguous(ambiguous)
                } else {
                    QueryResolution::Ambiguous(partial)
                }
            }
        }
    }
}

fn partial_matches<T, ExactKeys, ExactIter, Label>(
    query: &str,
    candidates: &[crate::matching::RankedMatch<T>],
    exact_keys: &ExactKeys,
    label: &Label,
) -> Vec<String>
where
    ExactKeys: Fn(&T) -> ExactIter,
    ExactIter: IntoIterator,
    ExactIter::Item: AsRef<str>,
    Label: Fn(&T) -> String,
{
    let query = query.to_lowercase();
    let mut seen = BTreeSet::new();
    let mut matches = Vec::new();
    for candidate in candidates {
        if exact_keys(&candidate.item)
            .into_iter()
            .any(|key| key.as_ref().to_lowercase().contains(query.as_str()))
        {
            let candidate_label = label(&candidate.item);
            if seen.insert(candidate_label.clone()) {
                matches.push(candidate_label);
            }
        }
    }
    matches
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, Clone, PartialEq, Eq)]
    struct Candidate {
        id: &'static str,
        name: &'static str,
    }

    #[test]
    fn resolves_unique_exact_match_across_multiple_keys() {
        let resolution = resolve_query(
            "setup-ci",
            vec![
                Candidate {
                    id: "api/setup-ci",
                    name: "setup-ci",
                },
                Candidate {
                    id: "api/release",
                    name: "release",
                },
            ],
            |candidate| [candidate.id.to_string(), candidate.name.to_string()],
            |candidate, query| crate::matching::fuzzy_score(candidate.id, query),
            |candidate| candidate.id,
            |candidate| candidate.id.to_string(),
        );

        assert_eq!(
            resolution,
            QueryResolution::Match(Candidate {
                id: "api/setup-ci",
                name: "setup-ci",
            })
        );
    }

    #[test]
    fn reports_ambiguous_top_ranked_candidates() {
        let resolution = resolve_query(
            "setup",
            vec![
                Candidate {
                    id: "api/setup-ci",
                    name: "setup-ci",
                },
                Candidate {
                    id: "web/setup-ci",
                    name: "setup-ci",
                },
            ],
            |candidate| [candidate.id.to_string(), candidate.name.to_string()],
            |candidate, query| crate::matching::fuzzy_score(candidate.id, query),
            |candidate| candidate.id,
            |candidate| candidate.id.to_string(),
        );

        assert_eq!(
            resolution,
            QueryResolution::Ambiguous(vec![
                "api/setup-ci".to_string(),
                "web/setup-ci".to_string(),
            ])
        );
    }

    #[test]
    fn ambiguous_fuzzy_query_reports_exact_partial_matches() {
        let resolution = resolve_query(
            "setup",
            vec![
                Candidate {
                    id: "api/setup-ci",
                    name: "setup-ci",
                },
                Candidate {
                    id: "web/setup-ci",
                    name: "setup-ci",
                },
                Candidate {
                    id: "docs/setup-guide",
                    name: "setup-guide",
                },
                Candidate {
                    id: "service/changelog",
                    name: "changelog",
                },
            ],
            |candidate| [candidate.id.to_string(), candidate.name.to_string()],
            |candidate, _query| match candidate.id {
                "api/setup-ci" | "web/setup-ci" => Some(10),
                "docs/setup-guide" => Some(5),
                "service/changelog" => Some(4),
                _ => None,
            },
            |candidate| candidate.id,
            |candidate| candidate.id.to_string(),
        );

        assert_eq!(
            resolution,
            QueryResolution::Ambiguous(vec![
                "api/setup-ci".to_string(),
                "web/setup-ci".to_string(),
                "docs/setup-guide".to_string(),
            ])
        );
    }
}
