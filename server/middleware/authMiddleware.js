module.exports = function (req, res, next) {
  if (req.session.userId) next();
  else res.status(401).json({ error: "Unauthorized" });
};