#ifndef HISHELL_DRAG_HELPER_H
#define HISHELL_DRAG_HELPER_H

#include <QColor>
#include <QImage>
#include <QObject>
#include <QPixmap>
#include <QString>
#include <QStringList>

class QTimer;

// Owns the platform QDrag for the QML file view. Qt Quick drag sources are
// QQuickItems; spring-loading replaces the view and deletes that item while Qt
// still owns the drag. Keeping QDrag here lets the drag survive the navigation,
// as the old DragDropHandler did.
class DragHelper : public QObject
{
	Q_OBJECT
public:
	explicit DragHelper(QObject *parent = nullptr);

	Q_INVOKABLE void startDrag(const QString &uri, const QString &imageUrl);
	Q_INVOKABLE void startDragFromGrab(QObject *grab, const QString &uri,
		const QColor &background);
	// URIs separated by newlines, for a multi-item selection handoff.
	Q_INVOKABLE void startDragManyFromGrab(QObject *grab, const QString &uris,
		const QColor &background);
	Q_INVOKABLE bool isSource(const QString &path) const;
	Q_INVOKABLE void setSpringTarget(const QString &path);
	Q_INVOKABLE void clearSpringTarget();

private:
	void performDrag(const QStringList &uris, const QPixmap &pixmap);
	QStringList m_sources;
	QString m_spring;
	QString m_action;
	QTimer *m_cursorTimer = nullptr;

signals:
	void dragFinished();
	void dragActionChanged(const QString &action);
	void cursorMoved(qreal x, qreal y);
	void springRequested(const QString &path);
};

extern "C" void hishell_register_drag_helper();

#endif
