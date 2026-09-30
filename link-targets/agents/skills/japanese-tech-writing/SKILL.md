---
name: japanese-tech-writing
description: Text standards for Japanese technical documents and book manuscripts. It stipulates formatting (sentence by line, quotation block, footnotes, column notation), paragraph and argument structure (paragraph writing), rigor of argument (elimination of tsukkomi), management of reader's load, point of view and narration, suppression of dramatization, prohibition of LLM-like blank phrases, and elimination of redundancy. Used when writing chapters, drafts, articles, and explanations of technical books in Japanese, or when revising or rewriting. It is intended for technical documents in Japanese that will be kept as deliverables, and will not be used for normal conversational responses, code reviews, PR/issues, commit messages, short reports on investigation progress or diagnosis results, unless the user explicitly requests that the text be revised.
---

# Text standards for Japanese technical documents

When writing or revising technical prose in Japanese (book chapters, articles, or explanatory text), follow these rules.

## Formatting

- Add a new line to each sentence. Paragraph breaks are indicated by blank lines.
- Fragments of code, differences, logs, and configuration files are shown in code blocks.
- Move supplementary details one step outside the main argument, such as the origin of a term or the name of a formulation, to footnotes (the `[^ラベル]` syntax) instead of listing them in the main text.
- Definitions and classifications may be listed in bullet points. Defined terms are in bold.
- When a term is defined or introduced for the first time in the text, put it in bold. When referring to a term already introduced as a topic, or in a quotation or common name, use Japanese corner brackets `「」` to distinguish it from bold (bold for the initial definition, `「」` for later mentions).
- Do not use dashes (em dash `—`, horizontal bar `―`, or the so-called double dash `——`) in Japanese prose or headings. For an inserted apposition such as `A——挿入——B`, use full-width parentheses `（）`; for paraphrase or elaboration such as `A——B`, split it into two sentences with a full stop or connect it with a comma. Range en dashes `–`, English compounds such as `Curry–Howard`, code blocks, and bibliographic information are excluded.
- Do not use the nakaguro (`・`, U+30FB) in Japanese parallel lists. However, it may be used within a single proper noun.
- Do not use separator lines (ruled lines `─` U+2500 or dashes) in headings or column headings to pack two elements together, as in `「種別──主題」` or `「主題──概念」`. Use a single natural phrase (one element, or elements connected by a particle or comma). Column headings should identify their subject rather than use only a category label such as `「基礎」` or `「補足」`; examples include `「同値関係としての分類」` and `「ループ不変条件と帰納法」`.
- For a bullet that lists a term and its definition, use a full-width colon as in `**用語**：説明`, not a separator line.

## Paragraph and argument structure

Basic paragraph writing. A paragraph is a step in an argument, and readers must be able to follow the logic paragraph by paragraph.

- Put only one topic in one paragraph. Long paragraphs that include multiple scene progressions (investigation, reporting, verification, evaluation) should be divided into paragraphs with each step.
- Make sure you can tell what a paragraph is about by reading the first sentence of it.
- At the beginning of a paragraph, use connective expressions to clarify the logical relationship with the previous paragraph (「であれば」 “if so”, 「実際」 “in fact”, 「しかし」 “however”, 「この例自体からも」 “from this example itself as well”).
- When introducing a new concept or terminology, do not start with a dictionary-style assertion that "X is Y." First, state the target in an introductory sentence, then state its function and differences, and if necessary, give a definition in the third sentence.
- The argument proceeds in one direction. Don't create a structure where you draw a conclusion, then deal with counterarguments and restate your conclusion. After dealing with counterarguments and doubts, draw a conclusion only once.
- Do not interrupt the flow by inserting excuses for the example (seems artificial, preemptive, etc.) right after the climax of the scene. Handle them all together at the beginning of the next section.
- Explicitly deny any false interpretations that readers might come up with, and then state the real reason (「その理由は『〜だから』ではない。〜だからだ」, “The reason is not ‘because…’; it is because…”).
- When denying something by saying “B rather than A,” add a sentence explaining the basis for the denial. Counterfactuals (「もしAなら、〜だっただろう」, “If A, it would have been…”) can often be used.
- Concessions (`「確かに〜」`, “Admittedly…” or “Indeed…”) are limited to acknowledging facts. It would be self-contradictory to assert that something that will be corrected later is cause and effect based on the author's voice. When you want to acknowledge a superficial diagnosis, you attribute it to the voice of the reader or conventional wisdom (「〜と要約できてしまうかもしれない」, “one might be tempted to summarize it as…”).
- Do not reveal in the preceding paragraph the information you want to land at the climax (numbers, unique facts).
- When denying or limiting a claim, quote the exact proposition you are rejecting using the Japanese corner brackets `「」` (for example, `「明文化されていればすべてを任せられる」`) and then state why it is false. Avoid vague denials such as `「何もかもが解決するわけではない」`.
- Forward references such as 「後の章で扱う」 (“will be covered in a later chapter”) should be placed at the end of the argument (at the end of a paragraph or section). Do not interrupt the flow of the argument by inserting it in the middle of the argument.

## Rigor of argument

There is no room for criticism in the logic of the text. Once you have finished writing, check the following points in advance of the reader's objections.

- Don't mechanically turn sentences written as conjectures, possibilities, readers' doubts, or counterfactuals into assertions.
  Delete Japanese hedges such as 「かもしれない」 (“may”), 「だろう」 (“probably/would”), 「ようだ」 (“seems”), and 「らしい」 (“apparently”) only when they weaken a claim without basis.
  When expressing the possibility of unconfirmed facts, recognition of characters in the story, inferences from logs, doubts that readers may have, or counterfactuals, maintain that uncertainty.
  A proposition can be changed to an assertion only if the proposition is established by evidence within the text.
  Bad example: Change 「提示し続けているかもしれない」 (“may continue to present”) to 「提示し続けている」 (“continues to present”).
  Good example: Keep the uncertainty, as in 「提示し続けている可能性がある」 (“there is a possibility that it continues to be presented”).
- Don't lump different things together as "the same." Don't lump objects that should be distinguished (separate decisions, different causes, different types of problems) into one word. Bad example: Writing three interdependent undecided items as "the same decision was made separately." Good example: "They are all separate decisions, but they are dependent on each other."
- Do not reduce events that have multiple factors to a single cause. If the example includes multiple types of problems, separate them and map which tool explains which. Bad example: An accident that combines the absence of a contract and a failure to conceal information is explained as a "problem of information concealment."
- Consistent treatment of the same concepts across chapters and sections. If you classify something as “decided by humans” in one section, don't write “agreed by the team” in another section. Classifications, definitions, and terms will have the same status throughout.
- When asserting cause and effect, state the mechanism (why it happens) in one sentence. Don't just write “If A, then B” and omit the reason. Bad example: "If you separate it by procedure, the change will spread throughout." Good example: "Each process shares the same expression for passing data, and changing that expression will affect the whole process."
- Do not write as if detection, guarantees, or resolution are 「必ず」 (“always”) possible. State them precisely with their conditions, as in 「〜しやすい」 (“tends to…”), 「〜できることが多い」 (“can often…”), or 「〜が成り立つときに限り」 (“only when … holds”).
- Make sure that the examples you give actually support your argument in its entirety. If an example supports only part of your argument, narrow the scope of your argument to fit the example.
- Make sure that points deferred with a phrase such as “to be dealt with in the next section” are actually addressed there. Do not plant foreshadowing that will not be paid off.
- After making concessions or limitations (「ただし」 “however”, 「とはいえ」 “that said”), always move forward with your argument. Don't end it with a reverse connection and leave it hanging in the air.
- Before using the key term of a section, state its definition and scope. Do not begin using it without defining it.
- When combining multiple concepts under a single hypernym, state in one sentence, just before naming it, that they all come down to the same thing.
  Also build a bridge for the reverse operation, breaking concepts apart (腑分け).

## Managing reader load

Treat the reader's memory and attention as finite resources.

- Do not give out unique names (file names, function names, identifiers) that do not need to be referenced later. Use general phrases like 「仕様書」 (“specification document”) and 「金額計算のユーティリティ」 (“amount calculation utility”).
- When the meaning of an abstract phrase cannot be determined uniquely from the context, use parentheses to identify it on the spot by inserting an appositive when possible, and avoid forcing the reader to read back as much as possible.
- When you add a new example or situation, giving the reader more context to retain, provide a convincing introduction by explaining what's different from the previous example and why you need another one.
- Avoid loading chapter openings and section introductions with excessive details that are not relevant to the examples that will be covered.
- Within an example section, omit only excessive details unrelated to that section's question or conclusion. Keep concrete details needed for the argument. Typical omissions include decorative precision in agent reports (time, HTTP status, coverage rate, etc.) and unique names that are not referenced later.

## Perspective and narrative

- In the example, write a series of actions with the actor as the subject (“I researched the repository, identified it, and found it”) rather than a list of results or a passive voice (“It was identified and found”).
- Don't use meaningless references to fictional characters such as "an engineer in his second year at the company."
- Do not refer to the reader as 「あなた」 (“you”) in your argument, but instead use their role name (「開発者」 “developer”, 「読者」 “reader”). Limit second-person addresses to a limited number of key points, such as the introduction to a scene (「〜としよう」, “suppose…”) and the conclusion of a chapter or book.
- Choose specific words that refer to the target. Don't blur it out with broad terms like "AI" or "tools."
- Once you introduce a formulation or terminology (K, contract, invariant condition, etc.) in a chapter or section, use that term from then on. Don't retreat to vague words like "context," "tool," and "AI" (it's good to use words like "context" as an introductory word before formulating things).
- For technical terms and translations, choose the established term used in the field. For example, call push notification delivery `配信`, not `配送`; do not pick a kanji compound of similar meaning by everyday intuition.
- When referring to a person, use the original spelling (Lehman, Bainbridge). However, when introducing a historical figure or a concept named after a person by its established name, use the common name in katakana, which is commonly used in Japanese.
- Do not use words that sound like technical terms in situations where they are not technical terms (such as calling the chain from a system to a human being a "route"). Write in normal terms, such as “the process of getting it to you” and “what's in between.”

## Restraint in presentation

These rules call for restraint, not a blanket ban on presentation techniques. Use rhetoric only where it is effective.

- Build suspense in the reasoning with a deliberate pause (“There is something lurking here”) or rhetorical questions only at key points where tension helps the discussion. Where an explanation is sufficient, state it directly.
- Do not overuse short, decisive lines as standalone paragraphs to create tension. A short sentence ending with a noun (such as “Only a few dozen seconds so far.”) may be used only at the climax of a scene.
- Avoid excessive use of bold emphasis in the text. Use it in only one or two places per section, at key points of the logic such as a negation or the conclusion of a section, to prevent misreading (it may also be used in the introduction). Otherwise, emphasize the order and structure of sentences.
- Rather than a commanding assertion such as 「〜してはならない」 (“must not…”), prefer a form that expresses the worker's own judgment, such as 「〜するわけにはいかない」 (“cannot very well…”).
- Don't make the turning point overly dramatic. A single sentence stating the facts is often sufficient. A short sentence with an exclamation mark is acceptable only at the peak of the discussion.
- Do not sensationalize accidents or danger by enumerating consequences.
- Do not announce your argument with a preface such as 「重要なのは〜である」 (“The important thing is…”) Write your argument as is. However, it is permissible to use a preface that declares the style of the argument (such as 「標語として言い換えれば」 “to restate it as a slogan”).
- Don't overuse the couplet phrase 「AではなくBだった」 (“It was B, not A”). Minor supplements and evaluations may be added in parentheses.
- Do not use phrases that are a twist on idiomatic expressions (such as “putting knowledge into your body”) or metaphors that do not have a unique meaning (such as “the world extends beyond the report”). Say it as it is, using simple verbs ("I'll learn it", "I'll have fewer chances to notice").

## Avoid LLM-like phrasing

Don't be seduced by the empty molds that LLMs churn out. Once you have written it, check it in this section.
It is a good idea to use the terminology from this book (本質的複雑さ “essential complexity”, 回収 “paying off/resolving”, 判断の配置 “placement of judgment”, etc.) in your discussion. The problem is that they are used as empty decorations.

Phrases like the following are typical of an LLM tone that adds no discussion points and only creates a sense of being “well written.” Do not use them.

- **Preview and summary**: 「重要なのは〜である」 (“What matters is…”), 「本章では〜を扱う／探求する」 (“This chapter covers/explores…”), 「ここでは〜について見ていく」 (“Here we will look at…”), 「まとめると」 (“In summary”), 「要するに」 (“In short,” when merely paraphrasing the preceding point), 「〜に他ならない」 (“nothing but…”).
- **正面から系 (head-on phrasing)**: 「正面から扱う」 (“handle head-on”), 「正面から回収する」 (“resolve head-on”), 「正面から見る／書く／立てる」 (“look at/write/set up head-on”)—declaring a posture instead of the substance.
- **Empty adjectives**: 「不可欠」 (“essential”), 「核心的」 (“core”), 「鍵となる」 (“key”), 「根本的な」 (“fundamental”) when they only emphasize without explaining the claim; 「多角的」 (“multifaceted”), 「包括的」 (“comprehensive”), 「総合的」 (“comprehensive/synthetic”) when they omit what is seen and how.
- **Empty verbs**: 「掘り下げる」 (“dig into”), 「深掘りする」 (“dig deeper”), 「言語化する」 (“put into words”) when they do not say what was written and how; 「触れる」 (“touch on”), 「言及する」 (“mention”) when they merely end a paragraph.
- **Connection patterns**: 「〜において」 (“in…”), 「〜という側面から」 (“from the aspect of…”), 「〜の観点から」 (“from the perspective of…”) when they add no information; repeated 「さらに」 (“furthermore”), 「また」 (“also”), and 「加えて」 (“in addition”).
- **Unsupported hedges and empty praise**: Avoid 「〜と言えるだろう」 (“one could say…”) and 「〜かもしれない」 (“may…”) when they weaken a claim without evidence; keep them for inferences, assumptions, readers' doubts, or a character's understanding. Avoid empty intensifiers such as 「非常に」 (“very”), 「極めて」 (“extremely”), and 「大いに」 (“greatly”) when they add no substance.

Bad examples: 「本章では、〇〇の理論を正面から扱う」 (“This chapter addresses the theory of X head-on”), 「この前提を、ここで正面から回収する」 (“We will resolve this premise head-on”), 「多角的に分析すると、重要なのは〜である」 (“When analyzed from multiple angles, what matters is…”).
Good examples: 「本章では、〇〇の理論を扱う」 (“This chapter covers the theory of X”), 「ここで、この前提を回収する」 (“Here, we resolve this premise”), 「評価の核心は、正しさを誰が知っているかにある」 (“The key to evaluation is who knows what is correct”).

## Eliminate redundancy

Avoid unnecessary sentences as much as possible.

- State each claim only once; do not repeat the same claim in different words.
- If adjacent sections say the same thing from different angles, their roles overlap. Absorb one into the other and combine them into a single section.
- Do not recapitulate the scene immediately after describing it. Include only one sentence that gives meaning (such as “You can be left almost completely in charge of this kind of work.”).
- Parallel facts that have the same logical role are combined into one sentence rather than being separated into separate sentences. The logical status of the group of facts is indicated by the first word in the sentence (“Of course, the accounting department's monthly processing and customer payments...”).
- Do not provide intermediate explanations that the reader can complete on their own.
- If you can compress an argument that spans several sentences into one sentence, leave only the compressed sentence. You may use 「要するに」 (“in short”) to signal a summary.
- Don't include sentences that are just for connection or evaluation (such as "That in itself is a good thing").
- Do not use questions and answers with an imaginary reader (such as asking a question and answering in one word) as rhetoric. State your claim as is. Similarly, avoid responding by acting out the reader's reaction (“You may have felt that way. That's right”), and make concessions in plain sentences (“Of course, the solution itself is not a matter for the developer to decide”).
- Don't introduce ideas that readers are likely to have in a meta framework (“There is a natural continuation of the story up to this point”, “This is an idea that...”). Write down the idea itself. If the reader has a question, you can write it as a question (「その保守も任せればよいのではないだろうか」, “Couldn't that maintenance be delegated as well?”).
- Do not write excuses or disclaimers for the author's position, such as “This book does not deny that.” Include only factual statements (“In many cases,...”).
- Write a sentence that can share the context with the reader in the shortest possible time. If you can understand the derivation without developing it step by step, give the structure a name and state it.
- Do not proactively bring up concepts or document names that have not yet been introduced in the main text.
- Don't settle for hesitant, weak predicates (such as 「有効な対策であり」 “this is an effective countermeasure”). State strongly and specifically what has been established based on the evidence in the text (e.g., 「活用において必須であり」 “It is essential for utilization”). However, weak predicates that express uncertainty, possibility, assumptions, and reader doubts are retained. Deliberate relaxation to adjust the tone (e.g., 「必須だと言ってもいい」 “I don't mind saying it's essential”) is acceptable.
- Conjunctive expressions that create the rhythm of a sentence (such as 「しかし一方で」 “but on the other hand”) are not considered redundant.

## How to add headings

Make headings specific to the content. Use a phrase that refers to the question the section answers or the subject it covers.

- Do not use headings that only describe the steps involved (such as “Go back to the example” or “Reread...”) or do not contain any information. Use a heading that describes the question the section answers or what it deals with.
- Don't make the heading a "line" that concludes the section. Avoid situations in which the reader knows the punch line at the beginning of the headline.
- It can also be a noun phrase that refers to the subject covered by the section.
- It doesn't matter whether the heading is interrogative or definitive. The question to ask is whether it refers to the subject matter or the question that the reader has.
- Choose questions or noun phrases that match the tone of the text.

## Honesty toward the reader

- When an example may seem contrived, acknowledge that it may look artificial and briefly explain why it is plausible.
- Base that explanation on general facts or conventional wisdom that appeal to the reader's own experience, such as `この症状は珍しくないだろう` or `〜という言い方もよく耳にする`, not on the author's assertion alone.
- Don't write smoothly as if you have confirmed something that you have not confirmed.
