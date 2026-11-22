-- Earlier versions kept the last character of the email domain. Full emails were
-- never stored, so the correct username suffix can only be refreshed at Apple sign-in.
-- Retain the known prefix and hide the incorrect suffix until that next sign-in.
UPDATE users SET email_mask = substr(email_mask, 1, 2) || '•••'
WHERE email_mask <> '•••';
