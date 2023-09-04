import pandas as pd
from io import StringIO

DATA = """
name,score
Alice,85
Bob,90
Charlie,87
Daisy,92
"""

df = pd.read_csv(StringIO(DATA))

async def app(scope, receive, send):
    path = scope['path']

    if path == '/':
        body = b'Uvicorn is working on root!'
    elif path == '/stats':
        mean_score = df["score"].mean()
        max_score = df["score"].max()
        min_score = df["score"].min()

        body = f"Mean Score: {mean_score}\nMax Score: {max_score}\nMin Score: {min_score}".encode()
    else:
        body = b'Not found'
        await send({
            'type': 'http.response.start',
            'status': 404,
            'headers': [
                [b'content-type', b'text/plain'],
            ],
        })
        await send({'type': 'http.response.body', 'body': body})
        return

    await send({
        'type': 'http.response.start',
        'status': 200,
        'headers': [
            [b'content-type', b'text/plain'],
        ],
    })
    await send({'type': 'http.response.body', 'body': body})
