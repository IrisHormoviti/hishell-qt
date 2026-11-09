#ifndef HISHELL_DRAG_HELPER_H
#define HISHELL_DRAG_HELPER_H

#include <QImage>
#include <QObject>
#include <QString>

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
	Q_INVOKABLE void startDragFromGrab(QObject *grab, const QString &uri);
	Q_INVOKABLE bool isSource(const QString &path) const;
	Q_INVOKABLE void setSpringTarget(const QString &path);
	Q_INVOKABLE void clearSpringTarget();

private:
	void performDrag(const QString &uri, const QImage &image);
	QString m_uri;
	QString m_spring;

signals:
	void dragFinished();
	void springRequested(const QString &path);
};

extern "C" void hishell_register_drag_helper();

#endif
