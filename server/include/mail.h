//flags for mails
#define SEEN     (1<<0)
#define ANSWERED (1<<1)
#define FLAGGED  (1<<2)
#define DELETED  (1<<3)
#define DRAFT    (1<<4)

//states for the imap-server
#define STATE_NONAUTHENTICATED 1
#define STATE_AUTHENTICATED 2
#define STATE_SELECTED 3
#define STATE_LOGOUT 4

//states for the smtp-server
#define STATE_INITIAL 1
#define STATE_IDENTIFIED 2
#define STATE_TRANSACTION 3
#define STATE_RECIPIENT 4
#define STATE_DATA 5
#define STATE_QUIT 6
