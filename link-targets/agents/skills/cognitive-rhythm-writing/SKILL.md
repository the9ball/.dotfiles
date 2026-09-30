---
name: cognitive-rhythm-writing
description: Rules for designing pacing in explanatory texts. It treats pacing not as decoration, but as switching cognitive modes (observation → hesitation → determination → re-observation) and managing unrecovered tension, and establishes the beat of a sentence, the density waveform of a paragraph, how to begin a section, distinguishing between loose sentences and useless sentences, and a mechanical inspection procedure after writing. It is used when generating chapters, articles, and explanatory text that you want to read as reading material, or when diagnosing and correcting texts that are 「密度はあるが平坦でおもしろくない」 (“dense but flat and uninteresting”). It is intended for long texts that should be read from the beginning, and should not be used for texts that prioritize searchability and quick response, such as API references, specification sheets, procedure manuals, runbooks, release notes, and short conversation answers.
---

# Japanese writing standards to create cognitive rhythm

Dense sentences become boring not because they contain a lot of information, but because the entire text is written in the same cognitive mode.
This norm creates a driving force for reading by intentionally switching the reader's cognitive mode (observing, wondering, believing, reconfirming) and always maintaining a “reason to continue reading.”

## Norms to be used together

Read `link-targets/agents/skills/japanese-tech-writing/SKILL.md` relative to repository-root before proceeding.

## Basic principle

- Pacing is designed not as an increase or decrease in the amount of information, but as a shift between cognitive modes. One unit is the cycle of observation → hesitation → determination → re-observation.
- The text always leaves open at least one unanswered tension (an unanswered question, an unsubstantiated belief, an answer promised to come back later). The moment all the tension is gone, the reader can stop reading.
- Write in the voice of a person involved in the process of thinking, rather than in the voice of someone explaining the completed conclusion. The reenactment of the writer's process of arriving at an answer becomes a reenactment of the reader's thinking.
- **Restrictions on the generation side**: When writing a new sentence by applying this norm, materials for beat, tension, and slack are only taken from the situation (events, data, and statements in the target world, and the narrator's state of judgment). Where no material is found in the situation, leave it flat without adding anything. Creating a rhythm with sentences that talk about the text itself (「〜の列挙はしない」 “I will not enumerate…”, 「問いは〜だけである」 “The only question is…”) is a violation of the norm, not an application. Run each newly created or reshaped sentence through the test in “How to distinguish slack from useless sentences” as soon as it is written.
- **The device is to be realized, not declared**: Do not write verbatim the name, procedure, or example sentence of a device described in this norm (such as 「答えの半分」 “half the answer”, 「緊張」 “tension”, 「回収」 “payoff”, 「問いを半分ずつ返す」 “return the question half at a time”) in the body text. “Answering questions in half” is achieved by writing the first half of the answer as the content. Sentences that declare the operations to be performed, such as 「先に答えを半分だけ置く」 (“lay only half the answer first”) and 「最後にもう一度だけ線を引く」 (“draw the line one last time”), are in themselves useless sentences. If the device is functioning properly, the reader will not be aware of its existence.
- **Situation in an explanatory text without a scene**: In an explanatory text without a narrative scene, the situation is the nature of the subject itself (data, calculations, trade-offs, naive expectations being violated by facts) and the inferences and counter-questions that the reader has. Tension is created from the nature of the subject (“Why doesn't fluency and correctness match?” is a question about the subject, so it's acceptable). Just because there is no scene, don't use it as a substitute for tension by talking about the progress of the text.
- **Do not let brevity bias dictate the prose**: Don't cut sentences to create a beat. Shortening the necessary shared context in the introduction (scope, perspective, comparison criteria, unresolved matters) is omission, not pacing. Edit to increase density only after the context has been established.

## Sentence beat

- Establish a foothold with short sentences, flow with long sentences, and stop with short sentences. Make “stand → flow → stop” the basic beat of the paragraph.
- Don't push through with just assertions. Alternate assertiveness and hesitation.
  - 断定：「〜だった」「〜である」「〜というわけだ」
    (English: Assertion: “It was,” “It is,” “That’s why.”)
  - 逡巡：「〜に違いない」（あとで裏切られる思い込み）、「〜とは思う。ただ…」「〜だろうか」
    (English: Hesitation: “It must be...” (a belief that is later betrayed), “I think so. I just...” “I wonder if...”)
- Hesitation is not a weakness, but a device. “Confidence that is later betrayed by facts” becomes a stepping stone for guiding readers' predictions and then destroying them.
  - Example: "I'm sure things are going well." → (in the next paragraph) "But when I looked at the record later, it wasn't."
- At the turning point, you can use the beat of “concession → turn → short stop” (“It will be ~. It will continue to be ~. However, what we are dealing with here is ~. That is what I want to think about.”). A short directive after the turn fixes the reader's gaze.

## Paragraph density waveform

- After two or three dense paragraphs, place one sparse paragraph. The functions of sparse paragraphs are limited to fixing a fixed item in one line, presenting the next judgment target, or switching the viewpoint distance.
- Do not fix the viewing distance. Alternate paragraphs that focus on specifics (records, numbers, statements, codes) and paragraphs that focus on meaning.
- Bullet points can be used not only to compress information, but also as “pauses” to stop the main text from breathing. The one-step sentence after the enumeration (“In short...”) is effective because of this pause.

## Opening design

- The opening's job is to create one unrecovered tension in the first few sentences. **Any type**. Examples of types that can be used:
  - From a restatement of the reader's actual feelings (“You may feel...”) to a hypothesis (“Maybe...”)
  - A direct question to the reader. However, don't leave anything behind and give your answer immediately.
  - A general proposition tinged with conviction. The rest of the text tests that belief.
  - A scene in which the narrator's assumptions are written down in a positive manner, and then broken down with facts.
  - Rephrasing the questions left in the previous chapter and section in the words of the parties involved
- Previews and summaries are not prohibited. One or two sentences that have an attitude (「〜を考えるうえで、これほど適切な切り口もないはずだ」 “there can be no better angle for thinking about…”, 「言い換えると〜という話である」 “in other words, the story is…”) can create tension in and of themselves. The only thing that should be prohibited is an agenda without attitude (「本章ではA、B、Cを扱う」 “This chapter deals with A, B, and C”).
- Any resistance that the reader may have (old, artificial, impractical, or irrelevant) should be stated first in the reader's own words, and then dealt with briefly before getting to the point.

## How to begin a section

- Do not declare at the beginning of a section, 「本節では〜を扱う」 (“This section deals with…”). Instead, enter one of the following:
  - Restate the sense of discomfort left by the previous section as a question for the person concerned.
  - Write down the counter-questions that the reader would naturally have ("Then, should I have done ~ beforehand?"). Do not answer immediately; first acknowledge the question ("I think that’s what I wanted to do"), then dismantle it with the argument that follows.
  - The story begins with the writer's confession (“To confess, I also had a plan to ...”). Confession is not used for self-criticism, but as a scaffold for the subsequent argument (“This plan is only half right”).
- Introduce theories, concepts, and quotations after creating a “unnamed sense of discomfort” in the reader. Theory is included as a name rather than an answer. Providing the theory first and confirming it with examples deprives the reader of discovery.
- Place the bridge between sections at the beginning of the next section, not at the end of the previous section. Adding a preview of the “next time” type at the end of the previous section is live commentary and a waste of time. If the next section opens with a counter-question, a sense of discomfort, or a confession, the reader will continue reading even without any preview.

## Enumeration landing

- Once you have listed the properties and classifications, do not leave the list hanging. Land each item, one by one, on the concrete scene just before it (「一つめは、さっき見た〜の正体である」 “the first is the true identity of the … we just saw”, 「二つめにも身に覚えがある」 “the second is also familiar”).
- Do not make the landing style uniform. Changes include pointing out the true identity, remembering it, relating it to unique facts, and giving up on the future.

## Collection and conclusion of questions

- Questions raised midway through should not be left unaddressed, but should be explicitly addressed. Answering questions in half (“This is half of the answer,” “The other half lies in…”) provides the driving force for the second half.
- The conclusion is to bring the accumulated abstractions to a concrete level that the reader already has (the opening scene, the reader's own experience, the question asked at the beginning), and then close the book. Don't stop at abstract theories and general rules.
- Selectively close the tension. You can leave one last thing open. Humility and delegation to the reader (“I want the reader to fill in the missing parts”) function as room for reader participation.
- Second-person address, requests to the reader (“Please take this as given”), and the writer's modesty or disclaimers function as breathing room only at boundaries such as the beginning or conclusion of a chapter. Do not mix them into the middle of an argument.

## How to distinguish slack from useless sentences

There is only one axis of judgment.
**Does the statement update a "situation" or a "document"?**

- Sentences that update the situation: Newly convey events, data, and people's statements in the target world, or the state of the narrator's judgment (beliefs, reservations, regrets, concessions, confessions). → You can leave it as a loose part.
- Sentences that update the document: Only tell what this chapter, this section, this explanation, and the story so far looks like and what to write next. → In principle, delete it.

Typical useless sentences (in both cases, the topic is the text itself, and there is no information about the situation):

- 「ここまでだと、概念の説明に見えるだろう。なので、すぐに例へ戻す。」（説明の見え方と執筆の予定）
  (English: "What I've read so far will seem like an explanation of a concept. So, I'll quickly return to the example." (How the explanation looks and what I plan to write))
- 「要するに、この章の主題は〜ではなく〜である。」（章の性格づけの言い直しだけで、対象の新情報がない）
  (English: "In short, the subject of this chapter is not..." (just a restatement of the chapter's characterization, no new information on the subject))
- 「誤解しないでほしいのだが、〜を否定したいわけではない。」（退ける誤読を特定しない弁明。下の例外1の形なら残せる）
  (English: "Don't get me wrong, I don't want to deny..." (An excuse that does not specify the misinterpretation to be dismissed. You can leave it in the form of Exception 1 below))
- 「テクニックの列挙はしない。」「〜の話ではない。問いは〜だけである。」（本文の性格・範囲の宣言。否定形でも短文でも、話題が本文自身なら駄文）
  (English: "I will not enumerate techniques." "This is not about .... The only question is ..." (Declaration of the character and scope of the text. Whether negative or short, if the topic is the text itself, it is useless))
- 「先に答えを半分だけ置く。」「最後にもう一度だけ線を引く。」（この規範の装置の実況。装置は内容で実現し、操作を宣言しない）
  (English: "Place only half the answer first." "Draw the line one last time." (Live commentary on this norm's devices. The device is realized by the content and does not declare its operation.))
- 「ここまでで〜は見えた。次の問いは〜である。」「次は〜を見る。」（節末の進行予告。節間の推進力は、次節の頭に置く反問・違和感で作る。前節の末尾で予告しない）
  (English: "Up to this point, I have seen ~. The next question is ~." "Next, I will look at ~." (A preview of the progress at the end of the section. The driving force between sections is created by the counter-question and sense of discomfort placed at the beginning of the next section. It is not announced at the end of the previous section.))

Bad sentences appear not only in the form of long explanatory sentences, but also in the form of short assertions.
Instead of deleting the document update sentence, if you format it into a short, assertive tone, it will look like a cliche line and will be more likely to remain. This is the biggest route for the introduction of junk.
Just because it's short and has a good rhythm is no reason to keep it. The quality of the beat is evaluated only for sentences that pass the topic test.

Typical examples of good slack (both update the situation or the narrator's state of judgment):

- 「うまくいっているに違いない。」（思い込み。あとで崩される布石）
  (English: “It must be going well.” (Belief. A foundation that will be broken later))
- 「まあ、今すぐ手を打つほどでもないのだけど、どこかの時点で整理は要るだろう。」（判断の保留という状態の更新）
  (English: "Well, it's not worth doing anything right now, but it will need to be sorted out at some point." (Updating the status of pending judgment))
- 「最初からわかっていたらそうしていたのに、というのが口惜しい。」（判断の誤差を可視化する感情）
  (English: “It frustrates me to realize I would have done that if I had known from the start.” (An emotion that makes the gap in judgment visible))
- 「そうしたかった、とは思う。」（反問への譲歩。直後の転回の足場）
  (English: “I think that’s what I wanted to do.” (Concession to the counter-question; scaffolding for the next turn))

Even in sentences that describe documents, only the following four forms can be retained.

1. **Counterargument handling**: Dismiss the reader's misinterpretation or counterargument by quoting it concretely in 「」 and rejecting it (for example, 「ここまでの話を『〜せよ』という主張と読まれると、それは違う」 “if what I have said so far is read as the claim ‘do…’, that is not right”). The condition is that the subject to be rejected is specifically cited. A vague sentence that just says “I hope you don't misunderstand me” is useless.
2. **Setting and collecting questions**: Place at the boundary, “In this chapter, we will think about ...” (only after creating tension), “This is half of the answer.” All that remains is the question itself and the collection statement. Declarations of “what the text is not” or “what it will not do” (“I will not enumerate...”, “This is not about...”) are not setting up questions. Delete unless specific misreading in the form of exception 1 is rejected.
3. **Request or disclaimer to the reader**: Place it at a boundary, for example, 「どうか〜と割り切って読んでほしい」 (“please read this while taking X as given”).
4. **Opening and closing the example frame**: Sentences that open (「〜としよう」 “suppose…”) and close (「冒頭の例にオチを付けておこう」 “let's add a punch line to the opening example”) of a hypothetical example/scene. It serves the function of reminding the reader that the example is fictitious and returning the abstract discussion to the scene. Place it at the boundary (beginning of the section). Even if the topic seems to be the main text itself, if you are manipulating the example frame, it is not a useless sentence.

Deletion and rewriting steps:

- When you find a sentence that just updates the document, first delete it, read the previous and subsequent sentences, and if it makes a connection, that's it.
- If the logic jumps due to deletion, replace the content the sentence was trying to refer with a sentence that describes the situation (“This seems like an explanation of a concept” → “All three qualities are present in the failure at the beginning”).
- If the resulting sentence still talks about the text itself (just shortened it or changed the wording), then the rewrite is a failure. Unless it fits into one of the exceptions 1 to 3, delete the entire sentence and bridge the front and back again.

## Inspection procedure after writing

After writing a draft, check it mechanically in the following order.

1. **Topic test**: Pick up the first sentence of a paragraph and all independent short sentences and judge whether they are updating the situation or the document. The document side will be deleted or rewritten unless it fits one of the three exception forms. Sentences that have been newly written or shortened during revision are likely to contain bad sentences, so they are also subjected to this test immediately after they are written.
2. **Leakage test**: Search the text for the exact Japanese vocabulary and example phrases from this standard (「答えの半分」(“half the answer”), 「緊張」(“tension”), 「回収」(“recovery”), 「線を引く」(“draw a line”), 「問いを〜返す」(“return a question”), etc.). If they appear, the device has been declared; delete that sentence and realize the device through the content instead. Also check the end of every section for a progress preview such as 「次は〜」 (“Next…”).
3. **Tension ledger**: List the questions, assumptions, and promises made in the text (such as 「答えは半分ずつ返す」 “I'll return the answer half at a time”), and point to the line where each is resolved. If you can't point to something, add the recovery or delete the question.
4. **Check the beat**: Look for three or more long assertions in a row and insert a short foothold, a pause, or a moment of hesitation.
5. **Check boundaries**: Check for second-person calls, requests, and modesty in the middle of the text. If so, move it to the boundary or delete it.

## How to use for correction instructions

When diagnosing flat prose, derive a remedy from the symptoms.

- **All the paragraphs have the same tone and are tiring**: There is no beat in the sentences. Apply inspection procedure 3.
- **I don't feel like reading on even though it's correct**: There is no unrecovered tension. Place one of the forms that create tension at the beginning, and check that one is always open from then on in the tension ledger.
- **The temperature suddenly drops at the theory section**: The theory appears before the sense of discomfort. Place a counter-question or confession before the theory, and land each enumerated item on a concrete scene.
- **It feels flabby even though it has slack sentences**: The flabbiness comes from sentences narrating progress. Take a topic test and rewrite the sentences to reflect the situation (minor differences in emotions, suspension of judgment, assumptions).
- **The end of the chapter is preachy**: It is closed as an abstract theory. Start with a sentence that connects the reader to something they already have, and end with one unanswered question.
- **Business-like opening**: An agenda with no attitude. Rather than cutting it down, give the preview a different attitude, or place a response to the reader's feelings and resistance before the preview.
