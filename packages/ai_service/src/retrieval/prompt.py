from langchain_core.prompts import ChatPromptTemplate

RAG_PROMPT = ChatPromptTemplate.from_messages([
    (
        "system",
        "你是一位嚴謹的知識庫助理。請僅根據以下參考資料回答問題。\n"
        "若參考資料中找不到答案，請明確說「根據現有資料，無法回答此問題」，不得憑空捏造。\n\n"
        "參考資料：\n{context}",
    ),
    ("human", "{question}"),
])
