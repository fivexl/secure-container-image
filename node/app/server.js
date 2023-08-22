const express = require('express');
const app = express();
const PORT = 80;

const data = [
  { name: 'Alice', score: 85 },
  { name: 'Bob', score: 90 },
  { name: 'Charlie', score: 87 },
  { name: 'Daisy', score: 92 }
];

app.get('/', (req, res) => {
  res.send('Express is working on root!');
});

app.get('/stats', (req, res) => {
  const meanScore = data.reduce((sum, item) => sum + item.score, 0) / data.length;
  const maxScore = Math.max(...data.map(item => item.score));
  const minScore = Math.min(...data.map(item => item.score));

  res.send(`Mean Score: ${meanScore}\nMax Score: ${maxScore}\nMin Score: ${minScore}`);
});

app.use((req, res) => {
  res.status(404).send('Not found');
});

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
